import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyRecorderView: View {
    @Bindable private var settings = Settings.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "Press keys…" : settings.hotkeyDisplay)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(minWidth: 90)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(recording ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(recording ? Color.accentColor : Color.secondary.opacity(0.3))
                )
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return event }
            let mods = carbonModifiers(from: event.modifierFlags)
            if mods & (cmdKey | controlKey | optionKey) == 0 {
                NSSound.beep(); return nil
            }
            settings.hotkeyKeyCode = Int(event.keyCode)
            settings.hotkeyModifiers = mods
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.shift)   { m |= shiftKey }
        if flags.contains(.option)  { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        return m
    }
}
