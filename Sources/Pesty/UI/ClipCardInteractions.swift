import AppKit
import SwiftUI

/// Select on the first click without waiting for the double-click recognizer.
/// A second click can still paste; modified clicks only change the selection.
struct ClipCardInteractions: ViewModifier {
    let select: () -> Void
    let extendSelection: () -> Void
    let toggleSelection: () -> Void
    let paste: () -> Void

    private var modifiers: NSEvent.ModifierFlags {
        NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
    }

    func body(content: Content) -> some View {
        content
            .onTapGesture(count: 2) {
                guard modifiers.intersection([.command, .shift]).isEmpty else { return }
                paste()
            }
            .simultaneousGesture(TapGesture().onEnded {
                if modifiers.contains(.command) {
                    toggleSelection()
                } else if modifiers.contains(.shift) {
                    extendSelection()
                } else {
                    select()
                }
            })
    }
}
