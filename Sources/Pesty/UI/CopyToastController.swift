import AppKit
import SwiftUI

@MainActor
final class CopyToastController {
    private let panel: NSPanel
    private let host: NSHostingView<CopyToastView>
    private var dismissWorkItem: DispatchWorkItem?

    init() {
        host = NSHostingView(rootView: CopyToastView(message: "", symbol: ""))
        host.sizingOptions = .intrinsicContentSize
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 236, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = host
    }

    /// A notice sized to its text; the default is the plain copy confirmation.
    func show(message: String = "Copied to Clipboard",
              symbol: String = "checkmark.circle.fill",
              linger: TimeInterval = 1.25) {
        dismissWorkItem?.cancel()
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        host.rootView = CopyToastView(message: message, symbol: symbol)
        let size = host.intrinsicContentSize
        if size.width > 0, size.height > 0 { panel.setContentSize(size) }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 34))
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }

        let dismiss = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWorkItem = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + linger, execute: dismiss)
    }

    private func dismiss() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        })
    }
}

private struct CopyToastView: View {
    let message: String
    let symbol: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.selection)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.28))
        }
    }
}
