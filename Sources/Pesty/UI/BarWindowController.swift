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

        // The panel stays parked at its final frame and the content slides up *inside*
        // it. Animating the window frame itself is not safe on multi-display setups:
        // the old staging rect (vf.minY - height) is only genuinely off-screen when
        // nothing sits below the target display. With displays stacked vertically it
        // lands on the neighbouring screen, so the bar appeared there in full and then
        // flew across the bezel. A view clipped to the window can never escape it.
        isHiding = false
        panel.setFrame(onScreen, display: false)
        guard let content = panel.contentView else { isPresenting = false; return }
        content.autoresizingMask = []
        content.frame = NSRect(x: 0, y: -height, width: onScreen.width, height: height)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            content.animator().frame = NSRect(x: 0, y: 0, width: onScreen.width, height: height)
        }, completionHandler: { [weak self] in
            DispatchQueue.main.async { self?.isPresenting = false }
        })
    }

    func hide() {
        guard let panel = window, panel.isVisible, !isHiding,
              let content = panel.contentView else { return }
        isHiding = true
        let down = NSRect(x: 0, y: -content.frame.height,
                          width: content.frame.width, height: content.frame.height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            content.animator().frame = down
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
