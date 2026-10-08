import CoreGraphics

/// Pure sizing rules shared by the Paste Bar's persisted preference and its
/// live-resize interaction.
enum BarResizeGeometry {
    static let defaultHeight = 430.0
    static let minimumHeight = 300.0
    static let maximumHeight = 720.0

    /// Returns a value which is safe to persist independently of the display
    /// the bar happens to be shown on.
    static func normalizedPersistedHeight(_ height: Double) -> Double {
        guard height.isFinite else { return defaultHeight }
        return min(maximumHeight, max(minimumHeight, height))
    }

    /// Applies the portable preference range first, then caps the result to
    /// the usable height of the target display.
    static func effectiveHeight(
        for requestedHeight: Double,
        in visibleFrame: CGRect
    ) -> CGFloat {
        let displayHeight = visibleFrame.height
        guard displayHeight.isFinite, displayHeight > 0 else { return 0 }
        return min(CGFloat(normalizedPersistedHeight(requestedHeight)), displayHeight)
    }

    /// Produces the complete bottom-docked panel frame for a target display.
    static func panelFrame(
        for requestedHeight: Double,
        in visibleFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: effectiveHeight(for: requestedHeight, in: visibleFrame)
        )
    }

    /// The macOS 26 glass surface extends below the panel so its lower corners
    /// remain clipped. Live resizing must preserve that oversized root view.
    static func presentedContentFrame(
        panelSize: CGSize,
        bottomExtension: CGFloat
    ) -> CGRect {
        let extensionHeight = max(0, bottomExtension)
        return CGRect(
            x: 0,
            y: -extensionHeight,
            width: panelSize.width,
            height: panelSize.height + extensionHeight
        )
    }
}

/// Immutable state captured at mouse-down so live resizing does not feed the
/// moving panel geometry back into the drag calculation.
struct BarResizeSession: Equatable {
    let initialPanelHeight: CGFloat
    let initialScreenY: CGFloat
    let visibleFrame: CGRect

    init(
        initialPanelHeight: CGFloat,
        initialScreenY: CGFloat,
        visibleFrame: CGRect
    ) {
        self.visibleFrame = visibleFrame
        self.initialPanelHeight = BarResizeGeometry.effectiveHeight(
            for: Double(initialPanelHeight),
            in: visibleFrame
        )
        self.initialScreenY = initialScreenY
    }

    /// Global macOS screen coordinates increase upward, so upward pointer
    /// travel adds to the bar height and downward travel subtracts from it.
    func height(atScreenY screenY: CGFloat) -> CGFloat {
        guard initialScreenY.isFinite, screenY.isFinite else {
            return initialPanelHeight
        }
        let requestedHeight = initialPanelHeight + (screenY - initialScreenY)
        return BarResizeGeometry.effectiveHeight(
            for: Double(requestedHeight),
            in: visibleFrame
        )
    }

    func frame(atScreenY screenY: CGFloat) -> CGRect {
        CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: height(atScreenY: screenY)
        )
    }

    /// The portable value to write only after a successful drag completes.
    func finalPersistedHeight(atScreenY screenY: CGFloat) -> Double {
        BarResizeGeometry.normalizedPersistedHeight(
            Double(height(atScreenY: screenY))
        )
    }

    var cancelledHeight: CGFloat { initialPanelHeight }

    var cancelledFrame: CGRect {
        CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: initialPanelHeight
        )
    }
}
