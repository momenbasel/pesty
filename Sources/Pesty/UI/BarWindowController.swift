import AppKit
import SwiftUI

final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class BarWindowController: NSWindowController, NSWindowDelegate {

    private var isPresenting = false

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

    func show() {
        guard let panel = window else { return }
        isPresenting = true
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first else { isPresenting = false; return }
        let vf = screen.visibleFrame
        let height = CGFloat(Settings.shared.barHeight)
        let onScreen = NSRect(x: vf.minX, y: vf.minY, width: vf.width, height: height)
        let offScreen = NSRect(x: vf.minX, y: vf.minY - height, width: vf.width, height: height)

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
        guard let panel = window, panel.isVisible else { return }
        let off = NSRect(x: panel.frame.minX, y: panel.frame.minY - panel.frame.height,
                         width: panel.frame.width, height: panel.frame.height)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(off, display: true)
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isPresenting, !AppController.shared.suppressAutoHide else { return }
        AppController.shared.hideBar()
    }
}
