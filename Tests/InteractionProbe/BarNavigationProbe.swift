import AppKit
import SwiftUI

/// Exercise the real strip, cards and store with disposable fixture history.
/// Run through scripts/check_bar_navigation.sh to isolate application support
/// and preferences. Clipboard polling and the production app delegate remain
/// inactive; navigation invokes the same store method used by the key handler.
@main
@MainActor
struct BarNavigationProbe {
    static var failures = 0
    static var scroll: NSScrollView?
    static var initialOffset: CGFloat = 0
    static var clickedOffset: CGFloat = 0

    static func check(_ condition: Bool, _ description: String) {
        if !condition { failures += 1 }
        print("\(condition ? "PASS" : "FAIL") \(description)")
        fflush(stdout)
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    static func mouse(_ type: NSEvent.EventType, window: NSWindow, point: NSPoint) {
        let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime,
                                      windowNumber: window.windowNumber, context: nil,
                                      eventNumber: 1, clickCount: 1,
                                      pressure: type == .leftMouseDown ? 1 : 0)!
        NSApp.postEvent(event, atStart: false)
    }

    static func escape(_ window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                    timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: window.windowNumber, context: nil,
                                    characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                    isARepeat: false, keyCode: 53)!
        NSApp.postEvent(event, atStart: false)
    }

    static func main() {
        guard let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"],
              URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath()
                == URL(fileURLWithPath: home).resolvingSymlinksInPath(),
              ClipboardStore.localBase.resolvingSymlinksInPath().path.hasPrefix(
                URL(fileURLWithPath: home).resolvingSymlinksInPath().path + "/"),
              FileManager.default.fileExists(atPath: home + "/.pesty-fixture") else {
            fputs("Refusing to run without an isolated home directory.\n", stderr)
            exit(1)
        }
        UserDefaults.standard.setVolatileDomain([
            "iCloudSync": false, "cloudKitSync": false,
            "historyLimit": 100, "showBarResizeHandle": false,
            "selectedClipPosition": 0
        ], forName: UserDefaults.argumentDomain)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let store = ClipboardStore.shared
        let items = (0..<40).map { ClipItem(type: .text, text: "Interaction fixture \($0)") }
        for item in items.reversed() { store.addCaptured(item) }
        store.selectFirst()
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 1000, height: 420),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let hosting = NSHostingView(rootView: BarView(searchBridge: BarSearchFieldBridge()))
        window.contentView = hosting
        window.orderFront(nil)
        app.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let scrolls = descendants(hosting).compactMap { $0 as? NSScrollView }
            for candidate in scrolls {
                print("Scroll: frame=\(candidate.frame), document=\(candidate.documentView?.frame ?? .zero), visible=\(candidate.documentVisibleRect)")
            }
            scroll = scrolls.max(by: { $0.contentSize.height < $1.contentSize.height })
            check(scroll != nil, "found actual strip scroll view")
            initialOffset = scroll?.documentVisibleRect.minX ?? -1
            mouse(.leftMouseDown, window: window, point: NSPoint(x: 400, y: 180))
            mouse(.leftMouseUp, window: window, point: NSPoint(x: 400, y: 180))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            check(store.selectedID == items[1].id, "actual card click selects second fixture")
            clickedOffset = scroll?.documentVisibleRect.minX ?? -1
            check(abs(clickedOffset - initialOffset) < 1, "actual mouse selection leaves scroll offset unchanged")
            store.moveSelection(by: 20)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            check(store.selectedID == items[21].id, "navigation selects offscreen fixture")
            check((scroll?.documentVisibleRect.minX ?? 0) > clickedOffset + 100, "actual strip scrolls after navigation")
            if let visible = scroll?.documentVisibleRect {
                let center = Theme.cardStripHorizontalPadding + CGFloat(21) * (Theme.cardWidth + Theme.cardSpacing) + Theme.cardWidth / 2
                check(visible.minX <= center && center <= visible.maxX, "offscreen selected card is revealed")
            }
            Settings.shared.selectedClipPosition = .rightEdge
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
            let trailing = Theme.cardStripHorizontalPadding + CGFloat(21) * (Theme.cardWidth + Theme.cardSpacing) + Theme.cardWidth
            check(abs((scroll?.documentVisibleRect.maxX ?? 0) - trailing) < 2, "right-edge preference aligns selected card")
            mouse(.rightMouseDown, window: window, point: NSPoint(x: 890, y: 180))
            mouse(.rightMouseUp, window: window, point: NSPoint(x: 890, y: 180))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.9) {
            let windows = app.windows.filter(\.isVisible)
            print("Visible windows after context click: \(windows.map { $0.className })")
            check(windows.contains(where: { $0.className.contains("Menu") }), "actual card context menu opens")
            escape(window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.6) {
            check(store.selectedID == items[21].id, "context menu does not change selection")
            check(!app.windows.contains(where: { $0.isVisible && $0.className.contains("Menu") }), "Escape dismisses context menu")
            print("Failures: \(failures)")
            exit(failures == 0 ? 0 : 1)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 12) {
            fputs("Bar audit timed out.\n", stderr)
            exit(1)
        }
        app.run()
    }
}
