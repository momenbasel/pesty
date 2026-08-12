#if MAS
import AppKit
import CloudKit
import CryptoKit
import Observation

/// CloudKit sync for the Mac App Store build. Bridges ClipboardStore to the
/// private database via CKSyncEngine (contract: docs/SYNC_DESIGN.md in the
/// iOS repo). Direct-download builds keep the iCloud Drive file sync instead.
@Observable
@MainActor
final class CloudSyncService {
    static let shared = CloudSyncService()

    private(set) var status: String = "Sync is off"

    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var store: ClipboardStore { ClipboardStore.shared }
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// recordName -> fingerprint of the last state pushed to (or accepted from) CloudKit.
    @ObservationIgnored private var shadow: [String: String] = [:]
    /// Suppresses the save-notification diff while a remote batch is applied.
    @ObservationIgnored private var isApplyingRemote = false

    private var stateURL: URL { ClipboardStore.localBase.appendingPathComponent("cksync-state.json") }
    private var shadowURL: URL { ClipboardStore.localBase.appendingPathComponent("cksync-shadow.json") }
    private var systemFieldsDir: URL { ClipboardStore.localBase.appendingPathComponent("ck-system-fields", isDirectory: true) }

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard engine == nil else { return }
        CKSchema.purgeTempAssets()
        try? FileManager.default.createDirectory(at: systemFieldsDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        shadow = loadShadow()
        let state = loadState()
        let config = CKSyncEngine.Configuration(
            database: CKContainer(identifier: CKSchema.containerID).privateCloudDatabase,
            stateSerialization: state,
            delegate: self)
        let engine = CKSyncEngine(config)
        self.engine = engine
        if state == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CKSchema.zoneID))])
        }
        status = "Sync is on"
        addObservers()
        refreshAccountStatus()
        diffAndEnqueue()
        Task { try? await engine.fetchChanges() }
    }

    func stop() {
        guard engine != nil else { return }
        removeObservers()
        engine = nil
        status = "Sync is off"
    }

    /// Manual enable from Settings. Drops the shadow map first so the next
    /// diff re-uploads every local item (Amendment 7 full reconcile).
    func enable() {
        shadow = [:]
        try? FileManager.default.removeItem(at: shadowURL)
        if engine == nil { start() } else { diffAndEnqueue() }
    }

    /// Amendment 6: never merge two accounts' clips. Wipe sync bookkeeping,
    /// turn the setting off; the user must re-enable manually.
    private func resetAfterAccountChange() {
        removeObservers()
        engine = nil
        shadow = [:]
        try? FileManager.default.removeItem(at: shadowURL)
        try? FileManager.default.removeItem(at: stateURL)
        try? FileManager.default.removeItem(at: systemFieldsDir)
        Settings.shared.cloudKitSync = false
        status = "iCloud account changed - re-enable sync in Settings"
    }

    private func addObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .pestyStoreDidSave, object: nil, queue: .main) { _ in
            Task { @MainActor in CloudSyncService.shared.diffAndEnqueue() }
        })
        observers.append(center.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { _ in
            Task { @MainActor in CloudSyncService.shared.refreshAccountStatus() }
        })
    }

    private func removeObservers() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
    }

    private func refreshAccountStatus() {
        let container = CKContainer(identifier: CKSchema.containerID)
        Task { @MainActor in
            let account = try? await container.accountStatus()
            guard engine != nil else { return }
            switch account {
            case .available:
                status = "Sync is on"
            case .noAccount:
                status = "Sign in to iCloud in System Settings to sync"
            case .restricted, .temporarilyUnavailable:
                status = "iCloud account unavailable — sync paused"
            default:
                status = "Checking iCloud account…"
            }
        }
    }

    // MARK: Local -> cloud

    private struct Desired {
        let fingerprint: String
        let isPinboard: Bool
    }

    func retainRemoteRecords(named names: [String]) {
        guard !names.isEmpty else { return }
        if engine == nil { shadow = loadShadow() }
        var changed = false
        for name in names where shadow.removeValue(forKey: name) != nil { changed = true }
        if changed { saveShadow() }
    }

    private func diffAndEnqueue() {
        guard let engine, !isApplyingRemote else { return }
        let desired = desiredRecords()
        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        for (name, rec) in desired where shadow[name] != rec.fingerprint {
            pending.append(.saveRecord(recordID(name)))
            shadow[name] = rec.fingerprint
        }
        for name in Array(shadow.keys) where desired[name] == nil {
            if store.isRetentionPruned(name) {
                shadow.removeValue(forKey: name)
                continue
            }
            pending.append(.deleteRecord(recordID(name)))
            shadow.removeValue(forKey: name)
            removeSystemFields(name)
        }
        guard !pending.isEmpty else { return }
        saveShadow()
        engine.state.add(pendingRecordZoneChanges: pending)
        // Don't wait for the engine's lazy schedule; a copy should be on the
        // server before the user reaches for the other device.
        Task { try? await engine.sendChanges() }
    }

    /// A clip pinned from history keeps its UUID, so one id can sit in both
    /// containers; the pinboard copy wins (record container = board id).
    private func desiredRecords() -> [String: Desired] {
        var out: [String: Desired] = [:]
        for board in store.pinboards {
            out[board.id.uuidString] = Desired(fingerprint: fingerprint(board), isPinboard: true)
            for item in board.items {
                out[item.id.uuidString] = Desired(
                    fingerprint: fingerprint(item, container: board.id.uuidString), isPinboard: false)
            }
        }
        for item in store.history where out[item.id.uuidString] == nil {
            out[item.id.uuidString] = Desired(
                fingerprint: fingerprint(item, container: CKSchema.historyContainerValue), isPinboard: false)
        }
        return out
    }

    private func lookupClip(recordName: String) -> (item: ClipItem, container: String)? {
        for board in store.pinboards {
            if let item = board.items.first(where: { $0.id.uuidString == recordName }) {
                return (item, board.id.uuidString)
            }
        }
        if let item = store.history.first(where: { $0.id.uuidString == recordName }) {
            return (item, CKSchema.historyContainerValue)
        }
        return nil
    }

    private func record(for recordID: CKRecord.ID) -> CKRecord? {
        let name = recordID.recordName
        if let board = store.pinboards.first(where: { $0.id.uuidString == name }) {
            let record = baseRecord(name: name, type: CKSchema.pinboardType)
            CKSchema.populate(record, from: board)
            return record
        }
        if let (item, container) = lookupClip(recordName: name) {
            let record = baseRecord(name: name, type: CKSchema.clipType)
            CKSchema.populate(record, from: item, container: container,
                              imageFileURL: item.type == .image ? store.imageURL(for: item) : nil)
            return record
        }
        engine?.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        return nil
    }

    // MARK: Cloud -> local

    private func handleFetchedRecordZoneChanges(_ event: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        var clips: [(ClipItem, container: String, imageSourceURL: URL?)] = []
        var boards: [Pinboard] = []
        for mod in event.modifications {
            let record = mod.record
            saveSystemFields(record)
            if let decoded = CKSchema.decodeClip(record) {
                clips.append((decoded.item, decoded.container, decoded.imageAssetURL))
            } else if let board = CKSchema.decodePinboard(record) {
                boards.append(board)
            }
        }
        var deletedIDs: [UUID] = []
        for del in event.deletions {
            removeSystemFields(del.recordID.recordName)
            if let id = UUID(uuidString: del.recordID.recordName) { deletedIDs.append(id) }
        }

        isApplyingRemote = true
        if !boards.isEmpty { store.applyRemote(pinboards: boards) }
        if !clips.isEmpty { store.applyRemote(clips: clips) }
        if !deletedIDs.isEmpty { store.applyRemoteDeletes(ids: deletedIDs) }
        isApplyingRemote = false

        reconcileShadow(clipIDs: clips.map { $0.0.id }, boardIDs: boards.map(\.id), deletedIDs: deletedIDs)
    }

    /// Records the applied remote state in the shadow map so the store's next
    /// save does not diff it back out. A remote clip dropped by dedupe (older
    /// duplicate) gets its record deleted, per the contract.
    private func reconcileShadow(clipIDs: [UUID], boardIDs: [UUID], deletedIDs: [UUID]) {
        let desired = desiredRecords()
        var pendingDeletes: [CKSyncEngine.PendingRecordZoneChange] = []
        for id in clipIDs {
            let name = id.uuidString
            if let rec = desired[name] {
                shadow[name] = rec.fingerprint
            } else if store.isRetentionPruned(name) {
                shadow.removeValue(forKey: name)
            } else {
                shadow.removeValue(forKey: name)
                removeSystemFields(name)
                pendingDeletes.append(.deleteRecord(recordID(name)))
            }
        }
        for id in boardIDs {
            let name = id.uuidString
            if let rec = desired[name] { shadow[name] = rec.fingerprint }
        }
        for id in deletedIDs { shadow.removeValue(forKey: id.uuidString) }
        saveShadow()
        if !pendingDeletes.isEmpty { engine?.state.add(pendingRecordZoneChanges: pendingDeletes) }
    }

    /// Conflict policy v1: server wins, local state rewritten from server.
    private func applyServerRecord(_ record: CKRecord) {
        saveSystemFields(record)
        isApplyingRemote = true
        if let decoded = CKSchema.decodeClip(record) {
            store.applyRemote(clips: [(decoded.item, decoded.container, decoded.imageAssetURL)])
            isApplyingRemote = false
            reconcileShadow(clipIDs: [decoded.item.id], boardIDs: [], deletedIDs: [])
        } else if let board = CKSchema.decodePinboard(record) {
            store.applyRemote(pinboards: [board])
            isApplyingRemote = false
            reconcileShadow(clipIDs: [], boardIDs: [board.id], deletedIDs: [])
        } else {
            isApplyingRemote = false
        }
    }

    // MARK: Zone recovery

    private func recreateZoneAndReupload() {
        guard let engine else { return }
        shadow.removeAll()
        saveShadow()
        try? FileManager.default.removeItem(at: systemFieldsDir)
        try? FileManager.default.createDirectory(at: systemFieldsDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: CKSchema.zoneID))])
        diffAndEnqueue()
    }

    // MARK: Fingerprints (deterministic across launches; Hasher is seeded)

    private func fingerprint(_ item: ClipItem, container: String) -> String {
        var hasher = SHA256()
        func feed(_ s: String) {
            hasher.update(data: Data(s.utf8))
            hasher.update(data: Data([0]))
        }
        feed(item.type.rawValue)
        feed(item.text ?? "")
        if let rtf = item.rtfData { hasher.update(data: rtf) }
        feed(item.imageFileName ?? "")
        feed(item.imageHash ?? "")
        feed(item.fileURLs.joined(separator: "|"))
        feed(item.colorHex ?? "")
        feed(item.sourceBundleID ?? "")
        feed(item.sourceAppName ?? "")
        feed(item.customTitle ?? "")
        feed(String(item.createdAt.timeIntervalSinceReferenceDate))
        feed(container)
        return hex(hasher.finalize())
    }

    private func fingerprint(_ board: Pinboard) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("pinboard\0\(board.name)\0\(board.colorHex)".utf8))
        return hex(hasher.finalize())
    }

    private func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: CKSchema.zoneID)
    }

    // MARK: Persistence

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    }

    private func loadShadow() -> [String: String] {
        guard let data = try? Data(contentsOf: shadowURL) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func saveShadow() {
        guard let data = try? JSONEncoder().encode(shadow) else { return }
        try? data.write(to: shadowURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: shadowURL.path)
    }

    private func systemFieldsURL(_ name: String) -> URL {
        systemFieldsDir.appendingPathComponent(name).appendingPathExtension("ckrecord")
    }

    private func saveSystemFields(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        let url = systemFieldsURL(record.recordID.recordName)
        try? coder.encodedData.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func removeSystemFields(_ name: String) {
        try? FileManager.default.removeItem(at: systemFieldsURL(name))
    }

    private func baseRecord(name: String, type: String) -> CKRecord {
        if let data = try? Data(contentsOf: systemFieldsURL(name)),
           let coder = try? NSKeyedUnarchiver(forReadingFrom: data) {
            coder.requiresSecureCoding = true
            if let record = CKRecord(coder: coder), record.recordType == type {
                return record
            }
        }
        return CKRecord(recordType: type, recordID: recordID(name))
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudSyncService: CKSyncEngineDelegate {
    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)

        case .accountChange(let change):
            switch change.changeType {
            case .signIn:
                refreshAccountStatus()
                diffAndEnqueue()
            case .signOut, .switchAccounts:
                resetAfterAccountChange()
            @unknown default:
                refreshAccountStatus()
            }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID.zoneName == CKSchema.zoneName {
                recreateZoneAndReupload()
            }

        case .fetchedRecordZoneChanges(let changes):
            handleFetchedRecordZoneChanges(changes)

        case .sentRecordZoneChanges(let sent):
            for record in sent.savedRecords {
                saveSystemFields(record)
            }
            for recordID in sent.deletedRecordIDs {
                removeSystemFields(recordID.recordName)
            }
            var hadRetryableFailure = false
            for failure in sent.failedRecordSaves {
                switch failure.error.code {
                case .serverRecordChanged:
                    if let server = failure.error.serverRecord {
                        applyServerRecord(server)
                    }
                case .zoneNotFound:
                    recreateZoneAndReupload()
                case .unknownItem:
                    removeSystemFields(failure.record.recordID.recordName)
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
                default:
                    // Retryable: drop the fingerprint so the next diff re-enqueues it.
                    shadow.removeValue(forKey: failure.record.recordID.recordName)
                    hadRetryableFailure = true
                }
            }
            if hadRetryableFailure {
                saveShadow()
                status = "Some items failed to upload - will retry"
            }
            CKSchema.purgeTempAssets()

        case .sentDatabaseChanges:
            break

        case .willFetchChanges, .willFetchRecordZoneChanges,
             .didFetchRecordZoneChanges, .didFetchChanges,
             .willSendChanges, .didSendChanges:
            break

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            await self?.record(for: recordID)
        }
    }
}
#endif
