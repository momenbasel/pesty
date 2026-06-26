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

        monitor.start()

        HotKeyCenter.shared.onTrigger = { [weak self] in self?.toggleBar() }
        HotKeyCenter.shared.start()

        setupStatusItem()

        if Settings.shared.launchAtLogin { LaunchAtLogin.set(enabled: true) }

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

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pesty")
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Pesty   \(Settings.shared.hotkeyDisplay)",
                     action: #selector(menuOpen), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Clear History", action: #selector(menuClear), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let about = menu.addItem(withTitle: "About Pesty", action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(withTitle: "Quit Pesty", action: #selector(menuQuit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func menuOpen() { showBar() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuClear() { store.clearHistory() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuAbout() { showAbout() }

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
        if let bar = barController, bar.window?.isVisible == true {
            hideBar()
        } else {
            showBar()
        }
    }

    func showBar() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
        store.searchText = ""
        store.source = .history
        store.selectFirst()

        if barController == nil {
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
        hideBar()
        PasteService.paste(item, into: previousApp, monitor: monitor)
    }

    func pasteItem(_ item: ClipItem) {
        hideBar()
        PasteService.paste(item, into: previousApp, monitor: monitor)
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
