import AppKit
import SwiftUI

/// A native event test kept separate from XCTest because it requires a GUI
/// login session. Compile it with the production ClipCardInteractions modifier
/// using scripts/check_card_interactions.sh.
@MainActor
private enum Probe {
    static var startedAt: TimeInterval = 0
    static var callbacks: [(action: String, milliseconds: Double)] = []
    static var failures = 0
    static var recording = false

    static func record(_ action: String) {
        guard recording else { return }
        callbacks.append((action, (ProcessInfo.processInfo.systemUptime - startedAt) * 1000))
    }
}

private struct ProbeCard: View {
    let original: Bool

    var body: some View {
        gestures
            .onDrag { NSItemProvider(object: "Pesty interaction fixture" as NSString) }
            .contextMenu { Button("Fixture menu item") {} }
    }

    private var card: some View {
        Color.blue
            .overlay(Text("Pesty interaction test").foregroundStyle(.white))
            .frame(width: 400, height: 180)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var gestures: some View {
        if original {
            card
                .onTapGesture(count: 2) { Probe.record("paste") }
                .onTapGesture { Probe.record("select") }
                .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { Probe.record("extend") })
                .highPriorityGesture(TapGesture().modifiers(.command).onEnded { Probe.record("toggle") })
        } else {
            card.modifier(ClipCardInteractions(
                select: { Probe.record("select") },
                extendSelection: { Probe.record("extend") },
                toggleSelection: { Probe.record("toggle") },
                paste: { Probe.record("paste") }))
        }
    }
}

@main
@MainActor
private struct CardInteractionProbe {
    private struct Scenario {
        let name: String
        var original = false
        var modifiers: NSEvent.ModifierFlags = []
        var doubleClick = false
        var releaseModifier = false
        let expected: [String]
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 400, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ProbeCard(original: true))
        window.orderFront(nil)
        app.activate(ignoringOtherApps: true)

        // Callback latency is an input responsiveness check, not a measurement
        // of rendered frames. Leave headroom for loaded development machines.
        let latencyLimit = ProcessInfo.processInfo.environment["PESTY_PROBE_MAX_LATENCY_MS"]
            .flatMap(Double.init) ?? 150
        guard latencyLimit.isFinite, latencyLimit > 0 else {
            fputs("PESTY_PROBE_MAX_LATENCY_MS must be a positive finite number.\n", stderr)
            exit(1)
        }
        let scenarios: [Scenario] = [
            Scenario(name: "original single click (comparison)", original: true, expected: ["select"]),
            Scenario(name: "single click", expected: ["select"]),
            Scenario(name: "double click", doubleClick: true, expected: ["select", "paste"]),
            Scenario(name: "Shift click", modifiers: .shift, expected: ["extend"]),
            Scenario(name: "Command click", modifiers: .command, expected: ["toggle"]),
            Scenario(name: "Command-Shift click", modifiers: [.command, .shift], expected: ["toggle"]),
            Scenario(name: "Shift double click", modifiers: .shift, doubleClick: true, expected: ["extend"]),
            Scenario(name: "Command double click", modifiers: .command, doubleClick: true, expected: ["toggle"]),
            Scenario(name: "original Shift click (comparison)", original: true, modifiers: .shift, expected: ["extend"]),
            Scenario(name: "original Shift release (comparison)", original: true, modifiers: .shift,
                     releaseModifier: true, expected: ["extend"]),
            Scenario(name: "Shift release", modifiers: .shift, releaseModifier: true, expected: ["extend"]),
            Scenario(name: "original Command release (comparison)", original: true, modifiers: .command,
                     releaseModifier: true, expected: ["toggle"]),
            Scenario(name: "Command release", modifiers: .command, releaseModifier: true, expected: ["toggle"])
        ]

        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Double-click interval: \(NSEvent.doubleClickInterval * 1000) ms")
        print("Maximum first-callback latency for updated handlers: \(latencyLimit) ms")
        fflush(stdout)

        for (index, scenario) in scenarios.enumerated() {
            let prepareAt = 0.5 + Double(index) * 1.3
            DispatchQueue.main.asyncAfter(deadline: .now() + prepareAt) {
                Probe.recording = false
                window.contentView = NSHostingView(rootView: ProbeCard(original: scenario.original))
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + prepareAt + 0.2) {
                Probe.callbacks = []
                Probe.startedAt = ProcessInfo.processInfo.systemUptime
                Probe.recording = true
                postClick(to: window, modifiers: scenario.modifiers, count: 1)
                if scenario.releaseModifier {
                    postModifierRelease(to: window, modifiers: scenario.modifiers)
                }
                if scenario.doubleClick {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        postClick(to: window, modifiers: scenario.modifiers, count: 2)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + prepareAt + 1) {
                Probe.recording = false
                let actions = Probe.callbacks.map(\.action)
                let timely = scenario.original
                    || Probe.callbacks.first.map { $0.milliseconds < latencyLimit } == true
                let passed = actions == scenario.expected && timely
                if !passed { Probe.failures += 1 }
                let timings = Probe.callbacks.map {
                    "\($0.action)@\(String(format: "%.1f", $0.milliseconds))ms"
                }.joined(separator: ", ")
                print("\(passed ? "PASS" : "FAIL") \(scenario.name): \(timings); expected \(scenario.expected)")
                fflush(stdout)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(scenarios.count) * 1.3) {
            print("\(scenarios.count) scenarios, \(Probe.failures) failures")
            exit(Probe.failures == 0 ? 0 : 1)
        }
        // A failed native gesture must not leave a test window stuck in a
        // nested event loop. This watchdog exits only this probe process.
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            fputs("Interaction probe timed out.\n", stderr)
            exit(1)
        }
        app.run()
    }

    private static func postClick(to window: NSWindow, modifiers: NSEvent.ModifierFlags, count: Int) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 200, y: 90),
                                          modifierFlags: modifiers,
                                          timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil,
                                          eventNumber: count, clickCount: count,
                                          pressure: type == .leftMouseDown ? 1 : 0)!
            NSApp.postEvent(event, atStart: false)
        }
    }

    private static func postModifierRelease(to window: NSWindow, modifiers: NSEvent.ModifierFlags) {
        let event = NSEvent.keyEvent(with: .flagsChanged, location: NSPoint(x: 200, y: 90),
                                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: window.windowNumber, context: nil,
                                    characters: "", charactersIgnoringModifiers: "",
                                    isARepeat: false, keyCode: modifiers == .shift ? 56 : 55)!
        NSApp.postEvent(event, atStart: false)
    }
}
