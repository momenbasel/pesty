import AppKit
import SwiftUI

/// A translucent stand-in for the Paste Bar, shown while the height slider in
/// Settings moves. Clicking into Settings dismisses the bar, so a number of
/// pixels is otherwise the only feedback available for a size that is only
/// meaningful on screen.
@MainActor
final class BarHeightGhostController {
    private static let lingerAfterChange: TimeInterval = 1.1

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(height: Double) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }

        let panel = panel ?? makePanel()
        self.panel = panel

        // Sized by the same rules the real bar uses, so the outline cannot
        // promise a height the display would not actually give.
        let frame = BarResizeGeometry.panelFrame(for: height, in: screen.visibleFrame)
        panel.setFrame(frame, display: true)
        (panel.contentView as? NSHostingView<BarHeightGhostView>)?.rootView =
            BarHeightGhostView(height: frame.height)
        // orderFrontRegardless keeps Settings key: this is a readout, and
        // stealing focus mid-drag would end the drag.
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lingerAfterChange, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isFloatingPanel = true
        panel.level = .modalPanel
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        // Purely a readout: it must never swallow a click meant for whatever
        // it happens to cover.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: BarHeightGhostView(height: 0))
        return panel
    }
}

private struct BarHeightGhostView: View {
    let height: CGFloat

    private var shape: RoundedCorners {
        RoundedCorners(radius: Theme.cornerRadius, corners: [.topLeft, .topRight])
    }

    var body: some View {
        ZStack {
            // The real bar, faded: judging a height is much easier against
            // actual cards than against an empty rectangle.
            BarView(searchBridge: BarSearchFieldBridge())
                .allowsHitTesting(false)
                .opacity(0.55)
            shape.stroke(Theme.selection, style: StrokeStyle(lineWidth: 2, dash: [9, 7]))
            VStack(spacing: 3) {
                Text("\(Int(height)) px")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Text("Paste Bar height")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
        }
        .ignoresSafeArea()
    }
}
