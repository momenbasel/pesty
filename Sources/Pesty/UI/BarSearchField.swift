import AppKit
import SwiftUI

/// Keeps the Paste Bar's native search field reachable while SwiftUI renders
/// it at a compact width. The local key monitor can therefore transfer first
/// responder synchronously and let the triggering key reach AppKit normally.
@MainActor
final class BarSearchFieldBridge {
    weak var field: NSTextField?

    func install(_ field: NSTextField) {
        self.field = field
    }

    func uninstall(_ field: NSTextField) {
        if self.field === field { self.field = nil }
    }

    @discardableResult
    func focusAtEnd() -> Bool {
        guard let field,
              let window = field.window,
              window.makeFirstResponder(field) else { return false }
        if let editor = field.currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        }
        return true
    }

    func resign() {
        guard let field,
              let window = field.window,
              let editor = field.currentEditor(),
              window.firstResponder === editor else { return }
        window.makeFirstResponder(nil)
    }

    func ownsFirstResponder(in window: NSWindow?) -> Bool {
        guard let window,
              let field,
              let editor = field.currentEditor() else { return false }
        return window.firstResponder === editor
    }
}

struct NativeBarSearchField: NSViewRepresentable {
    @Binding var text: String
    let bridge: BarSearchFieldBridge
    let onBegin: () -> Void
    let onEnd: () -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onMoveSelection: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.placeholderString = "Search"
        field.font = .systemFont(ofSize: 13, weight: .medium)
        // Matches Theme.chromeTextPrimary (Color.white.opacity(0.95)).
        field.textColor = NSColor.white.withAlphaComponent(0.95)
        let placeholderColor = NSColor.white.withAlphaComponent(0.55)
        field.placeholderAttributedString = NSAttributedString(
            string: "Search",
            attributes: [.foregroundColor: placeholderColor]
        )
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bridge.install(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        bridge.install(field)
        // Reassigning an equal value resets the native caret and selection.
        if field.stringValue != text { field.stringValue = text }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.parent.bridge.uninstall(field)
        field.delegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeBarSearchField

        init(parent: NativeBarSearchField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onBegin()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEnd()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  parent.text != field.stringValue else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl,
                     textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            if textView.hasMarkedText() { return false }

            if commandSelector == #selector(NSResponder.insertNewline(_:))
                || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            // The query is one line, so vertical arrows have no caret to move
            // and walk the strip instead. Horizontal arrows edit the query
            // until the caret reaches an end of it, then do the same.
            let caret = textView.selectedRange()
            let length = (textView.string as NSString).length
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onMoveSelection(-1)
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onMoveSelection(1)
                return true
            }
            if commandSelector == #selector(NSResponder.moveLeft(_:)),
               caret.length == 0, caret.location == 0 {
                parent.onMoveSelection(-1)
                return true
            }
            if commandSelector == #selector(NSResponder.moveRight(_:)),
               caret.length == 0, caret.location == length {
                parent.onMoveSelection(1)
                return true
            }
            return false
        }
    }
}
