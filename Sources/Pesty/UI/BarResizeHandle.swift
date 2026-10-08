import AppKit
import SwiftUI

/// Lets the Paste Bar's local key monitor leave Escape and drag-time keys to
/// the handle while it temporarily owns first-responder status.
protocol BarResizeHandleResponder: AnyObject {}

/// A compact drag target for resizing the Paste Bar vertically.
///
/// Drag callbacks use AppKit's global screen coordinate space so the owner can
/// keep its resize geometry independent of the handle's position in SwiftUI.
@MainActor
struct BarResizeHandle: View {
    private static let size = NSSize(width: 42, height: 14)

    private let accessibilityValue: CGFloat?
    private let onBegin: (NSPoint) -> Void
    private let onChange: (NSPoint) -> Void
    private let onEnd: (NSPoint) -> Void
    private let onCancel: () -> Void
    private let onAccessibilityAdjustment: (CGFloat) -> Void

    init(
        accessibilityValue: CGFloat? = nil,
        onBegin: @escaping (NSPoint) -> Void,
        onChange: @escaping (NSPoint) -> Void,
        onEnd: @escaping (NSPoint) -> Void,
        onCancel: @escaping () -> Void,
        onAccessibilityAdjustment: @escaping (CGFloat) -> Void
    ) {
        self.accessibilityValue = accessibilityValue
        self.onBegin = onBegin
        self.onChange = onChange
        self.onEnd = onEnd
        self.onCancel = onCancel
        self.onAccessibilityAdjustment = onAccessibilityAdjustment
    }

    var body: some View {
        BarResizeHandleRepresentable(
            accessibilityValue: accessibilityValue,
            callbacks: .init(
                onBegin: onBegin,
                onChange: onChange,
                onEnd: onEnd,
                onCancel: onCancel,
                onAccessibilityAdjustment: onAccessibilityAdjustment))
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

@MainActor
private struct BarResizeHandleRepresentable: NSViewRepresentable {
    let accessibilityValue: CGFloat?
    let callbacks: BarResizeHandleView.Callbacks

    func makeNSView(context: Context) -> BarResizeHandleView {
        BarResizeHandleView(callbacks: callbacks, accessibilityValue: accessibilityValue)
    }

    func updateNSView(_ nsView: BarResizeHandleView, context: Context) {
        nsView.callbacks = callbacks
        nsView.accessibilityHeight = accessibilityValue
    }
}

@MainActor
private final class BarResizeHandleView: NSView, BarResizeHandleResponder {
    static let accessibilityStep: CGFloat = 10

    struct Callbacks {
        let onBegin: (NSPoint) -> Void
        let onChange: (NSPoint) -> Void
        let onEnd: (NSPoint) -> Void
        let onCancel: () -> Void
        let onAccessibilityAdjustment: (CGFloat) -> Void
    }

    var callbacks: Callbacks
    var accessibilityHeight: CGFloat? {
        didSet { updateAccessibilityValue() }
    }

    private var isTrackingDrag = false
    private var ownsResizeCursor = false
    private weak var previousFirstResponder: NSResponder?

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 42, height: 14) }

    init(callbacks: Callbacks, accessibilityValue: CGFloat?) {
        self.callbacks = callbacks
        accessibilityHeight = accessibilityValue
        super.init(frame: NSRect(x: 0, y: 0, width: 42, height: 14))

        setAccessibilityElement(true)
        setAccessibilityRole(.slider)
        setAccessibilityLabel("Resize Paste Bar")
        setAccessibilityHelp("Drag vertically, or increment and decrement in ten-point steps.")
        updateAccessibilityValue()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) unavailable")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let line = NSRect(x: bounds.midX - 21, y: bounds.midY - 2, width: 42, height: 4)
        NSColor.secondaryLabelColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: line, xRadius: 2, yRadius: 2).fill()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func mouseDown(with event: NSEvent) {
        guard !isTrackingDrag else { return }
        isTrackingDrag = true
        previousFirstResponder = window?.firstResponder
        window?.makeFirstResponder(self)
        NSCursor.resizeUpDown.push()
        ownsResizeCursor = true
        callbacks.onBegin(screenPoint(for: event))
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingDrag else { return }
        callbacks.onChange(screenPoint(for: event))
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingDrag else { return }
        let point = screenPoint(for: event)
        finishTracking()
        callbacks.onEnd(point)
    }

    override func keyDown(with event: NSEvent) {
        guard isTrackingDrag, event.keyCode == 53 else {
            super.keyDown(with: event)
            return
        }
        cancelTracking()
    }

    override func cancelOperation(_ sender: Any?) {
        guard isTrackingDrag else {
            super.cancelOperation(sender)
            return
        }
        cancelTracking()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if isTrackingDrag, newWindow !== window {
            cancelTracking()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func accessibilityPerformIncrement() -> Bool {
        callbacks.onAccessibilityAdjustment(Self.accessibilityStep)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        callbacks.onAccessibilityAdjustment(-Self.accessibilityStep)
        return true
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard isTrackingDrag,
              let notificationWindow = notification.object as? NSWindow,
              notificationWindow === window else { return }
        cancelTracking()
    }

    private func cancelTracking() {
        guard isTrackingDrag else { return }
        finishTracking()
        callbacks.onCancel()
    }

    private func finishTracking() {
        isTrackingDrag = false
        if ownsResizeCursor {
            NSCursor.pop()
            ownsResizeCursor = false
        }
        if window?.firstResponder === self {
            window?.makeFirstResponder(previousFirstResponder)
        }
        previousFirstResponder = nil
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        guard let eventWindow = event.window else { return NSEvent.mouseLocation }
        return eventWindow.convertPoint(toScreen: event.locationInWindow)
    }

    private func updateAccessibilityValue() {
        let value = accessibilityHeight.map { NSNumber(value: Double($0)) }
        setAccessibilityValue(value)
    }
}
