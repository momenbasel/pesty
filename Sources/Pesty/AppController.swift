import AppKit
import SwiftUI
import Carbon.HIToolbox

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    static let shared = AppController()

    let store = ClipboardStore.shared
    let monitor = ClipboardMonitor()

    private var barController: BarWindowController?
    private var statusItem: NSStatusItem?
    private var pauseMenuItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var keyMonitor: Any?

    private(set) var previousApp: NSRunningApplication?
    private(set) var lastActiveApp: NSRunningApplication?

    var suppressAutoHide = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        monitor.start()

        HotKeyCenter.shared.onTrigger = { [weak self] in self?.toggleBar() }
        HotKeyCenter.shared.start()

        setMenuBarIconVisible(Settings.shared.showMenuBarIcon)

        if Settings.shared.launchAtLogin { LaunchAtLogin.set(enabled: true) }

        #if MAS
        // CKSyncEngine handles the push payloads itself; the app only registers.
        NSApplication.shared.registerForRemoteNotifications()
        if Settings.shared.cloudKitSync { CloudSyncService.shared.start() }
        #endif

        if CommandLine.arguments.contains("--demo") {
            store.seedDemo()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showBar()
            }
            return
        }

        if !Settings.shared.onboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showSettings()
            }
            Settings.shared.onboarded = true
        }
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastActiveApp = app
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    /// Reopening from Finder, Spotlight, or the Dock surfaces the app.
    ///
    /// The escape hatch comes first: Pesty is an accessory app, so with the status
    /// item hidden there is no Dock icon, no window, and no menu - and if the global
    /// hotkey failed to register because another app already owns the combination,
    /// there is no way back in at all short of deleting the preference from Terminal.
    /// Opening Pesty again brings the icon back and shows Settings so the user can
    /// fix whatever forced the relaunch.
    ///
    /// A normal reopen shows the Paste Bar - the primary interface should be
    /// discoverable without the keyboard shortcut. `hasVisibleWindows` cannot be
    /// trusted for that decision because the bar is an NSPanel, so ask the explicit
    /// presentation state instead; a duplicate reopen event coalesces naturally
    /// because `isPresented` flips as soon as the first show begins.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !Settings.shared.showMenuBarIcon {
            Settings.shared.showMenuBarIcon = true
            setMenuBarIconVisible(true)
            showSettings()
            return true
        }
        if barController?.isPresented != true {
            showBar()
        }
        return true
    }

    private func setupStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemIcon(item)
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Pesty   \(Settings.shared.hotkeyDisplay)",
                     action: #selector(menuOpen), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        let pause = menu.addItem(withTitle: "Pause Pesty", action: #selector(menuTogglePause), keyEquivalent: "")
        pause.target = self
        pauseMenuItem = pause
        menu.addItem(withTitle: "Clear History", action: #selector(menuClear), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let about = menu.addItem(withTitle: "About Pesty", action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(withTitle: "Quit Pesty", action: #selector(menuQuit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        if visible {
            setupStatusItem()
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func menuOpen() { showBar() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuClear() { store.clearHistory() }
    @objc private func menuTogglePause() { togglePestyPause() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuAbout() { showAbout() }

    func togglePestyPause() {
        monitor.togglePause()
        pauseMenuItem?.title = monitor.isPaused ? "Resume Pesty" : "Pause Pesty"
        if let item = statusItem { updateStatusItemIcon(item) }
    }

    private func updateStatusItemIcon(_ item: NSStatusItem) {
        item.button?.image = NSImage(
            systemSymbolName: monitor.isPaused ? "pause.circle" : "doc.on.clipboard",
            accessibilityDescription: "Pesty")
        item.button?.image?.isTemplate = true
    }

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Pesty",
            .applicationVersion: Bundle.main.appVersion,
            .credits: NSAttributedString(
                string: "A free, open-source clipboard manager for macOS.\nInspired by Paste.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)])
        ])
    }

    func toggleICloudSync() {
        let enabling = !Settings.shared.iCloudSync
        if enabling && !ClipboardStore.shared.iCloudAvailable {
            let alert = NSAlert()
            alert.messageText = "iCloud Drive Unavailable"
            alert.informativeText = "Sign in to iCloud and enable iCloud Drive in System Settings to sync your clipboard across your Macs."
            alert.runModal()
            return
        }
        Settings.shared.iCloudSync = enabling
        ClipboardStore.shared.setICloudSync(enabling)
    }

    static func restart() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    func toggleBar() {
        if let bar = barController, bar.isPresented {
            hideBar()
        } else {
            showBar()
        }
    }

    /// A sleep cycle can strand the bar mid-transition and can drop the Carbon hotkey.
    /// Reset both rather than trying to reason about what survived.
    @objc private func systemDidWake() {
        barController?.forceHide()
        stopKeyMonitor()
        HotKeyCenter.shared.reload()
    }

    /// Docking, undocking, and resolution changes can leave the bar sized for a screen
    /// that no longer exists. Drop it so the next open re-measures.
    ///
    /// This deliberately does NOT re-register the hotkey. That notification also fires
    /// for things as minor as a colour-profile change, and a transient
    /// RegisterEventHotKey failure during display churn would leave the app with no
    /// hotkey at all until the next relaunch - the exact bug this is meant to fix.
    @objc private func screenParametersChanged() {
        barController?.forceHide()
        stopKeyMonitor()
    }

    func showBar() {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, !isPesty(front) {
            previousApp = front
            lastActiveApp = front
        }
        store.searchText = ""
        store.source = .history
        store.selectFirst()

        // Rebuild if the panel was ever torn down - a nil window is another way the
        // bar silently stops appearing.
        if barController == nil || barController?.window == nil {
            barController = BarWindowController()
        }
        barController?.show()
        startKeyMonitor()
    }

    func hideBar() {
        stopKeyMonitor()
        barController?.hide()
    }

    func pasteSelected() {
        guard let item = store.selectedItem else { return }
        pasteItem(item)
    }

    /// The app that will receive a paste after the floating Pesty panel closes.
    /// `previousApp` is captured before the panel activates, while
    /// `lastActiveApp` covers menu-bar and reopen paths where it is unavailable.
    private var pasteTarget: NSRunningApplication? {
        [lastActiveApp, previousApp, NSWorkspace.shared.frontmostApplication]
            .compactMap { $0 }
            .first { !$0.isTerminated && !isPesty($0) }
    }

    private func isPesty(_ app: NSRunningApplication) -> Bool {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return true }
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return app.bundleIdentifier == bundleID
    }

    func pasteItem(_ item: ClipItem) {
        let target = pasteTarget
        hideBar()
        PasteService.paste(item, into: target, monitor: monitor)
    }

    func copyItem(_ item: ClipItem) {
        let change = PasteService.copy(item)
        monitor.suppressUntilChangeCount = change
        hideBar()
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if let win = settingsWindow {
            win.makeKeyAndOrderFront(nil)
            return
        }
        let view = SettingsView()
        let host = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: host)
        win.title = "Pesty Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 520, height: 560))
        win.center()
        win.isReleasedWhenClosed = false
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
    }

    /// Handles commands that only apply while the Paste Bar owns keyboard focus.
    /// The panel's key-equivalent path calls this before SwiftUI receives command keys.
    func handleBarCommandShortcut(_ event: NSEvent) -> Bool {
        guard barController?.window?.isKeyWindow == true else { return false }

        let flags = event.modifierFlags
        guard flags.contains(.command), flags.contains(.shift),
              !flags.contains(.control), !flags.contains(.option) else { return false }

        switch Int(event.keyCode) {
        case kVK_ANSI_S:
            showSettings()
            return true
        case kVK_ANSI_P:
            togglePestyPause()
            return true
        default:
            return false
        }
    }

    private func startKeyMonitor() {
        stopKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
    }

    private func stopKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // Events belonging to a native context menu, editor, alert, or the
        // Settings window must stay with their own responder chain. The bar
        // monitor is only responsible for keys delivered to the panel itself.
        guard event.window === barController?.window else { return event }

        if handleBarCommandShortcut(event) { return nil }

        let code = Int(event.keyCode)
        let flags = event.modifierFlags
        let cmd = flags.contains(.command)
        let ctrl = flags.contains(.control)
        let opt = flags.contains(.option)

        if cmd, let chars = event.charactersIgnoringModifiers, let n = Int(chars), (1...9).contains(n) {
            let items = store.visibleItems
            if n <= items.count { pasteItem(items[n - 1]) }
            return nil
        }

        switch code {
        case kVK_Escape:
            if !store.searchText.isEmpty { store.searchText = ""; store.selectFirst() }
            else { hideBar() }
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            pasteSelected(); return nil
        case kVK_LeftArrow, kVK_UpArrow:
            store.moveSelection(by: -1); return nil
        case kVK_RightArrow, kVK_DownArrow:
            store.moveSelection(by: 1); return nil
        case kVK_Delete:
            if cmd, let sel = store.selectedItem { store.delete(sel); return nil }
            if !store.searchText.isEmpty {
                store.searchText.removeLast(); store.selectFirst(); return nil
            }
            return nil
        case kVK_ForwardDelete:
            if let sel = store.selectedItem { store.delete(sel) }
            return nil
        default:
            break
        }

        if !cmd && !ctrl && !opt,
           let chars = event.characters, chars.count == 1,
           let scalar = chars.unicodeScalars.first,
           scalar.value >= 32, scalar.value != 127 {
            store.searchText.append(chars)
            store.selectFirst()
            return nil
        }
        return event
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
