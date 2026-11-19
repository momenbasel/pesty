import AppKit
import Carbon.HIToolbox

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x50535459

    private init() {}

    func start() {
        installHandlerIfNeeded()
        reload()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { HotKeyCenter.shared.onTrigger?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    /// Re-registers the global hotkey.
    ///
    /// The old registration has to be released before the new one can take the same
    /// combination, so a failed `RegisterEventHotKey` leaves the app with no hotkey at
    /// all. That is unrecoverable without a relaunch, and it is one of the ways the bar
    /// "stops opening" (issue #64). Another process can hold the combination briefly
    /// during login or a display change, so retry a few times before giving up, and put
    /// the old registration back if the new one will not take.
    func reload() {
        let previous = hotKeyRef
        unregister()

        let keyCode = UInt32(Settings.shared.hotkeyKeyCode)
        let modifiers = UInt32(Settings.shared.hotkeyModifiers)
        guard keyCode != 0 else { return }

        if register(keyCode: keyCode, modifiers: modifiers) { return }

        // Put the old one back so the user is never left without a hotkey, then retry.
        hotKeyRef = previous
        retryRegister(keyCode: keyCode, modifiers: modifiers, attemptsLeft: 5)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        let id = EventHotKeyID(signature: signature, id: 1)
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
        else { return false }
        hotKeyRef = ref
        return true
    }

    private func retryRegister(keyCode: UInt32, modifiers: UInt32, attemptsLeft: Int) {
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            let stale = self.hotKeyRef
            self.unregister()
            if self.register(keyCode: keyCode, modifiers: modifiers) { return }
            self.hotKeyRef = stale
            self.retryRegister(keyCode: keyCode, modifiers: modifiers, attemptsLeft: attemptsLeft - 1)
        }
    }

    private func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
    }

    static func describe(keyCode: Int, modifiers: Int) -> String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey  != 0 { s += "⌥" }
        if modifiers & shiftKey   != 0 { s += "⇧" }
        if modifiers & cmdKey     != 0 { s += "⌘" }
        s += keyName(for: keyCode)
        return s
    }

    static func keyName(for keyCode: Int) -> String {
        let map: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
            kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7",
            kVK_ANSI_8: "8", kVK_ANSI_9: "9",
            kVK_Space: String(localized: "Space"), kVK_Return: "↩", kVK_Escape: "⎋",
            kVK_ANSI_Period: ".", kVK_ANSI_Comma: ",", kVK_ANSI_Slash: "/"
        ]
        return map[keyCode] ?? "?"
    }
}
