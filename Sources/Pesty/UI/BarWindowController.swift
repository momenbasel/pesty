import AppKit
import SwiftUI

final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class BarWindowController: NSWindowController, NSWindowDelegate {

    private var isPresenting = false
    private var isHiding = false

    init() {
        let panel = BarPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 360),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.contentView = NSHostingView(rootView: BarView())
        super.init(window: panel)
        panel.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    /// The screen the bar should slide up from: the one under the pointer.
    ///
    /// `NSRect.contains` excludes a rect's max edges, so a pointer sitting exactly on
    /// the boundary between two displays matches none of them. Displays of differing
    /// sizes also leave unreachable gaps in the global coordinate space. Both cases
    /// used to fall through to `NSScreen.main`, which is the screen holding the *key
    /// window* — not the one the pointer is on — so the bar surfaced on the wrong
    /// display. Hit-test with `NSMouseInRect`, then fall back to the nearest screen.
    private static func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let hit = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return hit
        }
        return NSScreen.screens.min { a, b in
            distanceSquared(from: a.frame, to: mouse) < distanceSquared(from: b.frame, to: mouse)
        }
    }

    private static func distanceSquared(from rect: NSRect, to point: NSPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    func show() {
        guard let panel = window else { return }
        isPresenting = true
        guard let screen = Self.targetScreen() else { isPresenting = false; return }
        let vf = screen.visibleFrame
        let height = min(CGFloat(Settings.shared.barHeight), vf.height)
        let onScreen = NSRect(x: vf.minX, y: vf.minY, width: vf.width, height: height)
        let offScreen = NSRect(x: vf.minX, y: vf.minY - height, width: vf.width, height: height)

        // A hide() still animating owns the panel's frame. Repositioning under it makes
        // the panel interpolate from the old display's frame to the new one, so it
        // visibly flies across screens instead of sliding up. A zero-duration animation
        // replaces the in-flight one before we stage the slide.
        isHiding = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.animator().setFrame(offScreen, display: false)
        }
        panel.setFrame(offScreen, display: false)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(onScreen, display: true)
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async { self?.isPresenting = false }
        })
    }

    func hide() {
        guard let panel = window, panel.isVisible, !isHiding else { return }
        isHiding = true
        let off = NSRect(x: panel.frame.minX, y: panel.frame.minY - panel.frame.height,
                         width: panel.frame.width, height: panel.frame.height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(off, display: true)
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async {
                // show() may have re-staged the panel mid-animation; only retire it if
                // this hide is still the one in flight.
                guard self?.isHiding == true else { return }
                self?.isHiding = false
                panel.orderOut(nil)
            }
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isPresenting, !AppController.shared.suppressAutoHide else { return }
        AppController.shared.hideBar()
    }
}
