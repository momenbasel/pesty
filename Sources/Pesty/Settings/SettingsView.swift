import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 560)
    }
}

private struct PrivacySettings: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        Form {
            Section("Excluded Apps") {
                Text("Pesty will not save anything copied while one of these apps is frontmost. Copies made from a browser extension are attributed to the browser, so add that too if you use one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.ignoredSourceAppBundleIDs.isEmpty {
                    ContentUnavailableView("No apps excluded",
                                           systemImage: "hand.raised",
                                           description: Text("Add an app to keep its copied content out of Pesty."))
                        .padding(.vertical, 12)
                } else {
                    ForEach(settings.ignoredSourceAppBundleIDs, id: \.self) { bundleID in
                        ignoredAppRow(bundleID)
                    }
                }

                Button { chooseApps() } label: {
                    Label("Add App…", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func ignoredAppRow(_ bundleID: String) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIconProvider.icon(forBundleID: bundleID))
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(applicationName(for: bundleID))
                    .font(.system(size: 13, weight: .medium))
                Text(bundleID)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { settings.removeIgnoredSourceApp(bundleID) } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Allow clips from \(applicationName(for: bundleID))")
        }
        .padding(.vertical, 4)
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.title = "Exclude Apps from Pesty"
        panel.message = "Pesty will ignore copied content from the apps you choose."
        panel.prompt = "Add Apps"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                  bundleID != Bundle.main.bundleIdentifier else { continue }
            settings.addIgnoredSourceApp(bundleID)
        }
    }

    private func applicationName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let bundle = Bundle(url: url) else { return bundleID }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? bundleID
    }
}

private struct GeneralSettings: View {
    @Bindable private var settings = Settings.shared
    #if !MAS
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var requestedGrant = false

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    #endif

    var body: some View {
        Form {
            Section("Activation") {
                LabeledContent("Show Pesty") { HotkeyRecorderView() }
            }

            HistoryRetentionSettings()

            Section("Quick Paste") {
                LabeledContent("Paste items 1–9") {
                    HStack(spacing: 6) {
                        modifierPicker(selection: $settings.quickPasteModifier)
                        Text("+ 1…9").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Paste as plain text") {
                    modifierPicker(selection: $settings.plainTextModifier)
                }
                Text("Hold the plain-text modifier while using Quick Paste to strip formatting — with the defaults, ⌘⇧1 pastes the first clip as plain text. The two roles can never share a modifier; picking one that is taken swaps them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                #if !MAS
                Toggle("Paste directly into the active app", isOn: $settings.pasteDirectly)
                #endif
                Toggle("Ignore passwords (concealed clips)", isOn: $settings.ignoreConcealed)
                Toggle("Play sound on paste", isOn: $settings.playSound)
                Toggle("Play sound when copying from Pesty", isOn: $settings.playSoundOnCopy)
                Toggle("Hide Pesty when clicking outside", isOn: $settings.hideOnClickOutside)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Show Pesty in the menu bar", isOn: $settings.showMenuBarIcon)
                VStack(alignment: .leading) {
                    LabeledContent("Bar height", value: "\(Int(settings.barHeight)) px")
                    Slider(value: $settings.barHeight, in: 300...720, step: 10)
                }
                Toggle("Show resize handle on the Paste Bar", isOn: $settings.showBarResizeHandle)
                #if MAS
                Text("Select a clip to copy it, then press ⌘V to paste it into your app.")
                    .font(.caption).foregroundStyle(.secondary)
                #endif
            }

            Section("Clip Colors") {
                Picker("Color theme", selection: $settings.clipColorTheme) {
                    ForEach(ClipColorTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.clipColorTheme.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.clipColorTheme == .accentShades {
                    ColorPicker("Base color", selection: clipColorAccent, supportsOpacity: false)
                    HStack(spacing: 12) {
                        Text("Preview")
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            ForEach(Array(SourceColor.accentShades(for: settings.clipColorAccentHex).enumerated()),
                                    id: \.offset) { _, color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 13, height: 13)
                            }
                        }
                        .accessibilityLabel("Ten stable shades of the selected base color")
                    }
                    Text("Each source app keeps one of ten deterministic shades, so its cards stay recognizable without drifting too far from your chosen color.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Clip Navigation") {
                Picker("Selected clip position", selection: $settings.selectedClipPosition) {
                    ForEach(SelectedClipPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                .pickerStyle(.segmented)
                Text(settings.selectedClipPosition.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            #if MAS
            Section("Sync") {
                Toggle("Sync history with iCloud", isOn: Binding(
                    get: { settings.cloudKitSync },
                    set: { on in
                        settings.cloudKitSync = on
                        if on { CloudSyncService.shared.enable() } else { CloudSyncService.shared.stop() }
                    }))
                Text(CloudSyncService.shared.status)
                    .font(.caption).foregroundStyle(.secondary)
            }
            #else
            Section("Sync") {
                Toggle("Sync clipboard via iCloud Drive", isOn: Binding(
                    get: { settings.iCloudSync },
                    set: { _ in AppController.shared.toggleICloudSync() }))
                Text(ClipboardStore.shared.iCloudAvailable
                     ? "Keeps your history and pinboards in sync across your Macs through iCloud Drive."
                     : "Sign in to iCloud and enable iCloud Drive to use sync.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            #endif

            #if !MAS
            Section("Permissions") {
                HStack(spacing: 10) {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(accessibilityGranted ? .green : .orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                        Text(accessibilityGranted
                             ? "Granted — direct paste is enabled."
                             : (requestedGrant
                                ? "Waiting… toggle Pesty on in System Settings."
                                : "Required to paste directly into other apps."))
                            .font(.caption)
                            .foregroundStyle(accessibilityGranted ? .green : .secondary)
                    }
                    Spacer()
                    if !accessibilityGranted {
                        Button("Open Settings") {
                            requestedGrant = true
                            PasteService.ensureAccessibility(prompt: true)
                            openAccessibilityPane()
                        }
                    } else if requestedGrant {
                        Button("Restart Pesty") { AppController.restart() }
                    }
                }
            }
            #endif

            Section("Data") {
                Button("Clear Clipboard History", role: .destructive) {
                    ClipboardStore.shared.clearHistory()
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.barHeight) { _, height in
            AppController.shared.previewBarHeight(height)
        }
        #if !MAS
        .onAppear { accessibilityGranted = AXIsProcessTrusted() }
        .onReceive(poll) { _ in
            let now = AXIsProcessTrusted()
            if now != accessibilityGranted { accessibilityGranted = now }
        }
        #endif
    }

    #if !MAS
    private func openAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif

    private var clipColorAccent: Binding<Color> {
        Binding(
            get: { Color(hex: settings.clipColorAccentHex) ?? .pink },
            set: { settings.clipColorAccentHex = NSColor($0).hexString }
        )
    }

    private func modifierPicker(selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(ShortcutModifier.allCases) { modifier in
                Text("\(modifier.symbol) \(modifier.title)").tag(modifier.carbonValue)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 118)
    }
}

private struct HistoryRetentionSettings: View {
    private var settings = Settings.shared
    @State private var draftMode = Settings.shared.historyRetentionMode
    @State private var draftLimit = Settings.shared.historyLimit
    @State private var draftDays = Settings.shared.historyRetentionDays
    @State private var pendingRemovalCount = 0
    @State private var confirmingChange = false
    @State private var storageBytes: Int64?

    @State private var sliderValue = HistoryRetentionPreset(nearestDays: Settings.shared.historyRetentionDays).sliderIndex
    @State private var sliderEditing = false

    private var sliderPreset: HistoryRetentionPreset { HistoryRetentionPreset(sliderIndex: sliderValue) }

    private var storageSummary: String {
        let store = ClipboardStore.shared
        let count = store.history.count + store.pinboards.reduce(0) { $0 + $1.items.count }
        let clips = "\(count) clip\(count == 1 ? "" : "s")"
        guard let storageBytes else { return clips }
        return "\(clips) · \(ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))"
    }

    private func refreshStorageSize() async {
        let dir = ClipboardStore.shared.dataDirectory
        storageBytes = await Task.detached(priority: .utility) {
            Self.directorySize(at: dir)
        }.value
    }

    /// Walks the store directory off the main actor; images can make it
    /// large enough that a synchronous walk would hitch the Settings window.
    nonisolated private static func directorySize(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: url,
                                                              includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    var body: some View {
        Section {
            Picker("Limit history by", selection: $draftMode) {
                ForEach(HistoryRetentionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            if draftMode == .itemCount {
                Stepper(value: $draftLimit, in: 50...5000, step: 50) {
                    LabeledContent("Keep at most", value: "\(draftLimit) clips")
                }
            }
        } header: {
            Text("History")
        } footer: {
            // A grouped Form lays Section body rows out on a shared label/control
            // grid that clamps a bare Slider; the footer is plain full-width content.
            if draftMode != .itemCount {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Remove clips older than")
                        Spacer()
                        Text(sliderPreset.title)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.accentColor)
                    }
                    Slider(value: $sliderValue,
                           in: 0...Double(HistoryRetentionPreset.allCases.count - 1),
                           step: 1,
                           onEditingChanged: { editing in
                               sliderEditing = editing
                               if !editing { applySliderValue() }
                           })
                    HStack(spacing: 0) {
                        ForEach(HistoryRetentionPreset.allCases) { preset in
                            Text(preset.shortTitle)
                                .font(.system(size: 10, weight: preset == sliderPreset ? .bold : .medium))
                                .foregroundStyle(preset == sliderPreset ? Color.accentColor : .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, draftMode == .itemCount ? 0 : 4)
            LabeledContent("History and pinboards on disk", value: storageSummary)
        }
        .task {
            await refreshStorageSize()
            for await _ in NotificationCenter.default.notifications(named: .pestyStoreDidSave) {
                await refreshStorageSize()
            }
        }
        .onChange(of: draftMode) { evaluateDraft() }
        .onChange(of: draftLimit) { evaluateDraft() }
        .onChange(of: draftDays) { evaluateDraft() }
        .onChange(of: sliderValue) { if !sliderEditing { applySliderValue() } }
        .alert("Remove \(pendingRemovalCount) Clips?", isPresented: $confirmingChange) {
            Button("Remove \(pendingRemovalCount) Clips", role: .destructive) { commit() }
            Button("Cancel", role: .cancel) { revert() }
        } message: {
            Text("This setting removes \(pendingRemovalCount) clips from history on this Mac now, and keeps pruning automatically. Pinboards are not affected, and there is no undo.")
        }
    }

    private var footnote: String {
        #if MAS
        "Pruning tidies this Mac only — synced copies stay on your other devices. Pinned clips are never removed."
        #else
        "Pruning applies to this Mac's history. Pinned clips are never removed."
        #endif
    }

    private func evaluateDraft() {
        let count = ClipboardStore.shared.retentionRemovalCount(
            mode: draftMode, limit: draftLimit, days: draftDays)
        if count > 0 {
            pendingRemovalCount = count
            confirmingChange = true
        } else {
            commit()
        }
    }

    private func commit() {
        settings.historyRetentionMode = draftMode
        settings.historyLimit = draftLimit
        settings.historyRetentionDays = draftDays
        ClipboardStore.shared.applyRetentionPolicy()
    }

    private func revert() {
        draftMode = settings.historyRetentionMode
        draftLimit = settings.historyLimit
        draftDays = settings.historyRetentionDays
        sliderValue = HistoryRetentionPreset(nearestDays: draftDays).sliderIndex
    }

    private func applySliderValue() {
        let days = HistoryRetentionPreset(sliderIndex: sliderValue).days
        if days != draftDays { draftDays = days }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable().frame(width: 88, height: 88)
            Text("Pesty").font(.system(size: 26, weight: .bold))
            Text("Version \(Bundle.main.appVersion)")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("A free, open-source clipboard manager for macOS.\nInspired by Paste.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/momenbasel/pesty")!)
                Link("Report an Issue", destination: URL(string: "https://github.com/momenbasel/pesty/issues")!)
            }
            .padding(.top, 4)
            Button("Quit Pesty", role: .destructive) {
                NSApp.terminate(nil)
            }
            .padding(.top, 8)
            Spacer()
            Text("MIT Licensed · Made with SwiftUI")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
