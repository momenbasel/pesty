import AppKit
import Observation

extension Notification.Name {
    static let pestyStoreDidSave = Notification.Name("PestyStoreDidSave")
}

enum BarSource: Equatable {
    case history
    case pinboard(UUID)
}

@Observable
@MainActor
final class ClipboardStore {
    static let shared = ClipboardStore()

    private(set) var history: [ClipItem] = []
    private(set) var pinboards: [Pinboard] = []

    var source: BarSource = .history
    var searchText: String = ""
    var selectedID: UUID?

    /// Bumped every time the bar is about to present. The hosting view is
    /// built once and cached, so the strip keeps its scroll offset across
    /// hide/show; selection alone cannot reset it because the newest clip is
    /// usually already selected and `onChange` never fires for equal values.
    private(set) var barPresentationToken = 0

    var historyLimit: Int {
        get { Settings.shared.historyLimit }
        set { Settings.shared.historyLimit = newValue; trimHistory() }
    }

    private var storeURL: URL
    private var imagesDir: URL
    private var baseDir: URL
    private var saveWorkItem: DispatchWorkItem?

    private var fileWatch: DispatchSourceFileSystemObject?
    private var ignoreWatchUntil: Date = .distantPast

    static var localBase: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pesty", isDirectory: true)
    }

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    static var iCloudBase: URL? {
        guard !isSandboxed else { return nil }
        let p = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: p.path) else { return nil }
        return p.appendingPathComponent("Pesty", isDirectory: true)
    }

    var iCloudAvailable: Bool { ClipboardStore.iCloudBase != nil }

    private init() {
        let base = (Settings.shared.iCloudSync ? ClipboardStore.iCloudBase : nil) ?? ClipboardStore.localBase
        baseDir = base
        imagesDir = base.appendingPathComponent("images", isDirectory: true)
        storeURL = base.appendingPathComponent("store.json")
        prepareDirectories()
        load()
        if Settings.shared.iCloudSync { startWatching() }
    }

    private func prepareDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: baseDir.path)
    }

    var visibleItems: [ClipItem] {
        let base: [ClipItem]
        switch source {
        case .history:
            base = history
        case .pinboard(let id):
            base = pinboards.first(where: { $0.id == id })?.items ?? []
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { $0.searchableText.contains(q) }
    }

    var selectedItem: ClipItem? {
        guard let id = selectedID else { return nil }
        return visibleItems.first(where: { $0.id == id })
    }

    func addCaptured(_ item: ClipItem) {
        if let idx = history.firstIndex(where: { $0.sameContent(as: item) }) {
            if item.imageFileName != history[idx].imageFileName { deleteImageFile(item) }
            var existing = history.remove(at: idx)
            existing.createdAt = item.createdAt
            history.insert(existing, at: 0)
            if source == .history && searchText.isEmpty { selectedID = existing.id }
            scheduleSave()
            return
        }
        history.insert(item, at: 0)
        trimHistory()
        if source == .history && searchText.isEmpty {
            selectedID = item.id
        }
        scheduleSave()
    }

    func applyHistoryLimit() { trimHistory(); scheduleSave() }

    private func trimHistory() {
        guard history.count > historyLimit else { return }
        let removed = Array(history[historyLimit...])
        history.removeLast(history.count - historyLimit)
        for item in removed { deleteImageFile(item) }
    }

    /// Deletes a clip from the collection currently on screen only. A Pinboard
    /// is an independently saved collection: deleting a card from history must
    /// not erase saved copies, and deleting a pinboard copy must not touch
    /// history or other pinboards, even for legacy clips that share an id.
    /// Deleting exactly what was removed also closes an image-file leak: the
    /// old cross-container removal deleted entries under two file names but
    /// cleaned up only one of them.
    func delete(_ item: ClipItem) {
        let removed: [ClipItem]
        switch source {
        case .history:
            removed = history.filter { $0.id == item.id }
            history.removeAll { $0.id == item.id }
        case .pinboard(let boardID):
            guard let boardIndex = pinboards.firstIndex(where: { $0.id == boardID }) else { return }
            removed = pinboards[boardIndex].items.filter { $0.id == item.id }
            pinboards[boardIndex].items.removeAll { $0.id == item.id }
        }
        for entry in removed { deleteImageFile(entry) }
        if selectedID == item.id { selectFirst() }
        scheduleSave()
    }

    func clearHistory() {
        let old = history
        history.removeAll()
        selectedID = nil
        for item in old { deleteImageFile(item) }
        scheduleSave()
    }

    @discardableResult
    func addPinboard(name: String, colorHex: String = "#5B8DEF") -> Pinboard {
        let b = Pinboard(name: name, colorHex: colorHex)
        pinboards.append(b)
        scheduleSave()
        return b
    }

    func renamePinboard(_ id: UUID, to name: String) {
        guard let i = pinboards.firstIndex(where: { $0.id == id }) else { return }
        pinboards[i].name = name
        scheduleSave()
    }

    func deletePinboard(_ id: UUID) {
        guard let i = pinboards.firstIndex(where: { $0.id == id }) else { return }
        if case .pinboard(let cur) = source, cur == id { source = .history }
        let removedItems = pinboards[i].items
        pinboards.remove(at: i)
        for item in removedItems { deleteImageFile(item) }
        scheduleSave()
    }

    func saveToPinboard(_ item: ClipItem, boardID: UUID) {
        guard let i = pinboards.firstIndex(where: { $0.id == boardID }) else { return }
        if pinboards[i].items.contains(where: { $0.sameContent(as: item) }) { return }
        // Pinboard copies mint their own UUID (one sync record per container).
        var copy = ClipItem(
            type: item.type,
            text: item.text,
            rtfData: item.rtfData,
            imageFileName: item.imageFileName,
            imageHash: item.imageHash,
            fileURLs: item.fileURLs,
            colorHex: item.colorHex,
            sourceBundleID: item.sourceBundleID,
            sourceAppName: item.sourceAppName,
            customTitle: item.customTitle,
            createdAt: item.createdAt)
        if let dup = duplicateImageFile(item) { copy.imageFileName = dup }
        pinboards[i].items.insert(copy, at: 0)
        scheduleSave()
    }

    func setTitle(_ title: String, for item: ClipItem) {
        if let i = history.firstIndex(where: { $0.id == item.id }) { history[i].customTitle = title }
        for b in pinboards.indices {
            if let i = pinboards[b].items.firstIndex(where: { $0.id == item.id }) {
                pinboards[b].items[i].customTitle = title
            }
        }
        scheduleSave()
    }

    func selectFirst() { selectedID = visibleItems.first?.id }

    func prepareForBarPresentation() {
        barPresentationToken &+= 1
        selectFirst()
    }

    func moveSelection(by delta: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        guard let id = selectedID, let idx = items.firstIndex(where: { $0.id == id }) else {
            selectedID = items.first?.id; return
        }
        let next = max(0, min(items.count - 1, idx + delta))
        selectedID = items[next].id
    }

    func imageURL(for item: ClipItem) -> URL? {
        guard let name = item.imageFileName else { return nil }
        return imagesDir.appendingPathComponent(name)
    }

    func loadImage(for item: ClipItem) -> NSImage? {
        guard let url = imageURL(for: item) else { return nil }
        return NSImage(contentsOf: url)
    }

    func storeImageData(_ data: Data) -> String? {
        let name = "\(UUID().uuidString).png"
        let url = imagesDir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return name
        } catch { return nil }
    }

    private func duplicateImageFile(_ item: ClipItem) -> String? {
        guard let src = imageURL(for: item), FileManager.default.fileExists(atPath: src.path) else { return nil }
        let name = "\(UUID().uuidString).png"
        let dst = imagesDir.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: src, to: dst)
            return name
        } catch {
            return nil
        }
    }

    private func deleteImageFile(_ item: ClipItem) {
        guard let name = item.imageFileName else { return }
        let stillUsed = history.contains { $0.imageFileName == name }
            || pinboards.contains { $0.items.contains { $0.imageFileName == name } }
        if stillUsed { return }
        if let url = imageURL(for: item) { try? FileManager.default.removeItem(at: url) }
    }

    private struct Snapshot: Codable {
        var history: [ClipItem]
        var pinboards: [Pinboard]
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        history = snap.history
        pinboards = snap.pinboards
        selectFirst()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        let snap = Snapshot(history: history, pinboards: pinboards)
        guard let data = try? JSONEncoder().encode(snap) else { return }
        ignoreWatchUntil = Date().addingTimeInterval(1.5)
        try? data.write(to: storeURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
        NotificationCenter.default.post(name: .pestyStoreDidSave, object: nil)
    }

    // MARK: - Remote (CloudKit) apply

    /// Applies decoded CloudKit clips. Dedupe by contentKey keeps the newer
    /// createdAt; insertion stays newest-first. Callers update their own
    /// last-synced bookkeeping so these changes do not loop back into sync.
    func applyRemote(clips: [(ClipItem, container: String, imageSourceURL: URL?)]) {
        guard !clips.isEmpty else { return }
        for entry in clips {
            let item = entry.0
            // The per-app exclusion list is local to each Mac and is not synced, so a
            // clip from an ignored app copied on another device would otherwise arrive
            // here and land in history anyway. A privacy filter that leaks across
            // devices is not a privacy filter.
            guard !Settings.shared.isIgnoringSourceApp(item.sourceBundleID) else { continue }
            if let src = entry.imageSourceURL, let name = item.imageFileName {
                let dst = imagesDir.appendingPathComponent(name)
                try? FileManager.default.removeItem(at: dst)
                try? FileManager.default.copyItem(at: src, to: dst)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dst.path)
            }
            if entry.container == "history" {
                applyRemoteToHistory(item)
            } else if let boardID = UUID(uuidString: entry.container) {
                applyRemoteToPinboard(item, boardID: boardID)
            }
        }
        trimHistory()
        if selectedID == nil { selectFirst() }
        scheduleSave()
    }

    func applyRemoteDeletes(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        let removedHistory = history.filter { set.contains($0.id) }
        history.removeAll { set.contains($0.id) }
        var removedPinned: [ClipItem] = []
        for i in pinboards.indices {
            removedPinned += pinboards[i].items.filter { set.contains($0.id) }
            pinboards[i].items.removeAll { set.contains($0.id) }
        }
        let removedBoards = pinboards.filter { set.contains($0.id) }
        pinboards.removeAll { set.contains($0.id) }
        if case .pinboard(let cur) = source, set.contains(cur) { source = .history }
        for item in removedHistory + removedPinned + removedBoards.flatMap(\.items) {
            deleteImageFile(item)
        }
        if let sel = selectedID, set.contains(sel) { selectFirst() }
        scheduleSave()
    }

    /// Upserts pinboard name/color only; item membership syncs through clip records.
    func applyRemote(pinboards boards: [Pinboard]) {
        guard !boards.isEmpty else { return }
        for b in boards {
            if let i = pinboards.firstIndex(where: { $0.id == b.id }) {
                pinboards[i].name = b.name
                pinboards[i].colorHex = b.colorHex
            } else {
                pinboards.append(Pinboard(id: b.id, name: b.name, colorHex: b.colorHex, items: []))
            }
        }
        scheduleSave()
    }

    private func applyRemoteToHistory(_ item: ClipItem) {
        let replaced = history.filter { $0.id == item.id }
        history.removeAll { $0.id == item.id }
        let key = contentKey(item)
        if let dupIdx = history.firstIndex(where: { contentKey($0) == key }) {
            let dup = history[dupIdx]
            if dup.createdAt >= item.createdAt {
                deleteImageFile(item)
                for old in replaced { deleteImageFile(old) }
                return
            }
            history.remove(at: dupIdx)
            deleteImageFile(dup)
        }
        insertSortedByDate(item, into: &history)
        // Same-id replace: drop the old image file unless something still uses it.
        for old in replaced { deleteImageFile(old) }
    }

    private func applyRemoteToPinboard(_ item: ClipItem, boardID: UUID) {
        // Placeholder board if the clip record arrives before its Pinboard record.
        if !pinboards.contains(where: { $0.id == boardID }) {
            pinboards.append(Pinboard(id: boardID, name: "Pinboard", items: []))
        }
        guard let i = pinboards.firstIndex(where: { $0.id == boardID }) else { return }
        // Legacy shared-id records: a pinboard clip also evicts the same id from history.
        var replaced = history.filter { $0.id == item.id }
        history.removeAll { $0.id == item.id }
        replaced += pinboards[i].items.filter { $0.id == item.id }
        pinboards[i].items.removeAll { $0.id == item.id }
        let key = contentKey(item)
        if let dupIdx = pinboards[i].items.firstIndex(where: { contentKey($0) == key }) {
            let dup = pinboards[i].items[dupIdx]
            if dup.createdAt >= item.createdAt {
                deleteImageFile(item)
                for old in replaced { deleteImageFile(old) }
                return
            }
            pinboards[i].items.remove(at: dupIdx)
            deleteImageFile(dup)
        }
        insertSortedByDate(item, into: &pinboards[i].items)
        // Same-id replace: drop the old image file unless something still uses it.
        for old in replaced { deleteImageFile(old) }
    }

    private func insertSortedByDate(_ item: ClipItem, into items: inout [ClipItem]) {
        let idx = items.firstIndex(where: { $0.createdAt < item.createdAt }) ?? items.endIndex
        items.insert(item, at: idx)
    }

    func setICloudSync(_ enabled: Bool) {
        stopWatching()
        let target = (enabled ? ClipboardStore.iCloudBase : ClipboardStore.localBase) ?? ClipboardStore.localBase
        let newImages = target.appendingPathComponent("images", isDirectory: true)
        let newStore = target.appendingPathComponent("store.json")
        let fm = FileManager.default
        try? fm.createDirectory(at: newImages, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])

        if fm.fileExists(atPath: newStore.path),
           let data = try? Data(contentsOf: newStore),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            copyImages(from: imagesDir, to: newImages)
            baseDir = target; imagesDir = newImages; storeURL = newStore
            mergeExternal(snap)
        } else {
            copyImages(from: imagesDir, to: newImages)
            baseDir = target; imagesDir = newImages; storeURL = newStore
            saveNow()
        }
        prepareDirectories()
        if enabled { startWatching() }
    }

    private func copyImages(from src: URL, to dst: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) else { return }
        for f in files where f.pathExtension == "png" {
            let target = dst.appendingPathComponent(f.lastPathComponent)
            if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: f, to: target) }
        }
    }

    private func contentKey(_ item: ClipItem) -> String {
        switch item.type {
        case .image: return "img:" + (item.imageHash ?? item.imageFileName ?? item.id.uuidString)
        case .color: return "col:" + (item.colorHex ?? "")
        case .file:  return "file:" + item.fileURLs.joined(separator: "|")
        default:     return "txt:" + (item.text ?? "")
        }
    }

    private func mergeExternal(_ snap: Snapshot) {
        let before = history.count
        var combined = (history + snap.history).sorted { $0.createdAt > $1.createdAt }
        var seen = Set<String>()
        var merged: [ClipItem] = []
        for it in combined where seen.insert(contentKey(it)).inserted { merged.append(it) }
        history = Array(merged.prefix(historyLimit))

        var byID: [UUID: Pinboard] = Dictionary(uniqueKeysWithValues: pinboards.map { ($0.id, $0) })
        for b in snap.pinboards {
            if var existing = byID[b.id] {
                for it in b.items where !existing.items.contains(where: { $0.sameContent(as: it) }) {
                    existing.items.append(it)
                }
                byID[b.id] = existing
            } else {
                byID[b.id] = b
            }
        }
        pinboards = pinboards.map { byID[$0.id] ?? $0 }
            + byID.values.filter { b in !pinboards.contains(where: { $0.id == b.id }) }

        combined.removeAll()
        selectFirst()
        if history.count != before || !snap.history.isEmpty { saveNow() }
    }

    private func startWatching() {
        stopWatching()
        let fd = open(storeURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            if Date() < self.ignoreWatchUntil { return }
            if let data = try? Data(contentsOf: self.storeURL),
               let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
                self.mergeExternal(snap)
            }
            self.startWatching()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        fileWatch = src
    }

    private func stopWatching() {
        fileWatch?.cancel()
        fileWatch = nil
    }
}
