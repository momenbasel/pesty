import AppKit
import Carbon.HIToolbox
import Observation

enum ShortcutModifier: CaseIterable, Identifiable {
    case command
    case option
    case control
    case shift

    var id: Int { carbonValue }

    var carbonValue: Int {
        switch self {
        case .command: return cmdKey
        case .option: return optionKey
        case .control: return controlKey
        case .shift: return shiftKey
        }
    }

    var title: String {
        switch self {
        case .command: return "Command"
        case .option: return "Option"
        case .control: return "Control"
        case .shift: return "Shift"
        }
    }

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    init?(carbonValue: Int) {
        guard let modifier = Self.allCases.first(where: { $0.carbonValue == carbonValue }) else {
            return nil
        }
        self = modifier
    }
}

@Observable
@MainActor
final class Settings {
    static let shared = Settings()

    @ObservationIgnored private let d = UserDefaults.standard
    @ObservationIgnored private var isLoaded = false

    enum Keys {
        static let historyLimit = "historyLimit"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let quickPasteModifier = "quickPasteModifier"
        static let plainTextModifier = "plainTextModifier"
        static let launchAtLogin = "launchAtLogin"
        static let hideOnClickOutside = "hideOnClickOutside"
        static let pasteDirectly = "pasteDirectly"
        static let playSound = "playSound"
        static let ignoreConcealed = "ignoreConcealed"
        static let ignoredSourceAppBundleIDs = "ignoredSourceAppBundleIDs"
        static let barHeight = "barHeight"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let onboarded = "onboarded"
        static let iCloudSync = "iCloudSync"
        static let cloudKitSync = "cloudKitSync"
    }

    var historyLimit: Int {
        didSet {
            guard isLoaded else { return }
            if historyLimit < 20 { historyLimit = 20; return }
            d.set(historyLimit, forKey: Keys.historyLimit)
            ClipboardStore.shared.applyHistoryLimit()
        }
    }

    var hotkeyKeyCode: Int {
        didSet { guard isLoaded else { return }
            d.set(hotkeyKeyCode, forKey: Keys.hotkeyKeyCode); HotKeyCenter.shared.reload() }
    }

    var hotkeyModifiers: Int {
        didSet { guard isLoaded else { return }
            d.set(hotkeyModifiers, forKey: Keys.hotkeyModifiers); HotKeyCenter.shared.reload() }
    }

    var quickPasteModifier: Int {
        didSet {
            guard isLoaded else { return }
            if quickPasteModifier == plainTextModifier { plainTextModifier = oldValue }
            d.set(quickPasteModifier, forKey: Keys.quickPasteModifier)
        }
    }

    var plainTextModifier: Int {
        didSet {
            guard isLoaded else { return }
            if plainTextModifier == quickPasteModifier { quickPasteModifier = oldValue }
            d.set(plainTextModifier, forKey: Keys.plainTextModifier)
        }
    }

    var launchAtLogin: Bool {
        didSet { guard isLoaded else { return }
            d.set(launchAtLogin, forKey: Keys.launchAtLogin); LaunchAtLogin.set(enabled: launchAtLogin) }
    }

    var hideOnClickOutside: Bool {
        didSet { guard isLoaded else { return }; d.set(hideOnClickOutside, forKey: Keys.hideOnClickOutside) }
    }

    var pasteDirectly: Bool {
        didSet { guard isLoaded else { return }; d.set(pasteDirectly, forKey: Keys.pasteDirectly) }
    }

    var playSound: Bool {
        didSet { guard isLoaded else { return }; d.set(playSound, forKey: Keys.playSound) }
    }

    var ignoreConcealed: Bool {
        didSet { guard isLoaded else { return }; d.set(ignoreConcealed, forKey: Keys.ignoreConcealed) }
    }

    /// Applications whose copied content should never be recorded in history.
    /// Store bundle identifiers rather than paths so the choice continues to work
    /// when an app is updated or moved.
    private(set) var ignoredSourceAppBundleIDs: [String] {
        didSet { guard isLoaded else { return }; d.set(ignoredSourceAppBundleIDs, forKey: Keys.ignoredSourceAppBundleIDs) }
    }

    var barHeight: Double {
        didSet {
            guard isLoaded else { return }
            let clamped = min(720, max(240, barHeight))
            if clamped != barHeight { barHeight = clamped; return }
            d.set(barHeight, forKey: Keys.barHeight)
        }
    }

    var showMenuBarIcon: Bool {
        didSet {
            guard isLoaded else { return }
            d.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon)
            AppController.shared.setMenuBarIconVisible(showMenuBarIcon)
        }
    }

    var onboarded: Bool {
        didSet { guard isLoaded else { return }; d.set(onboarded, forKey: Keys.onboarded) }
    }

    var iCloudSync: Bool {
        didSet { guard isLoaded else { return }; d.set(iCloudSync, forKey: Keys.iCloudSync) }
    }

    var cloudKitSync: Bool {
        didSet { guard isLoaded else { return }; d.set(cloudKitSync, forKey: Keys.cloudKitSync) }
    }

    private init() {
        d.register(defaults: [
            Keys.historyLimit: 500,
            Keys.hotkeyKeyCode: kVK_ANSI_V,
            Keys.hotkeyModifiers: cmdKey | shiftKey,
            Keys.quickPasteModifier: cmdKey,
            Keys.plainTextModifier: shiftKey,
            Keys.launchAtLogin: false,
            Keys.hideOnClickOutside: true,
            Keys.pasteDirectly: true,
            Keys.playSound: false,
            Keys.ignoreConcealed: true,
            Keys.ignoredSourceAppBundleIDs: [],
            Keys.barHeight: 430.0,
            Keys.showMenuBarIcon: true,
            Keys.onboarded: false,
            Keys.iCloudSync: false,
            Keys.cloudKitSync: true
        ])
        historyLimit = d.integer(forKey: Keys.historyLimit)
        hotkeyKeyCode = d.integer(forKey: Keys.hotkeyKeyCode)
        hotkeyModifiers = d.integer(forKey: Keys.hotkeyModifiers)
        quickPasteModifier = d.integer(forKey: Keys.quickPasteModifier)
        plainTextModifier = d.integer(forKey: Keys.plainTextModifier)
        launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
        hideOnClickOutside = d.bool(forKey: Keys.hideOnClickOutside)
        pasteDirectly = d.bool(forKey: Keys.pasteDirectly)
        playSound = d.bool(forKey: Keys.playSound)
        ignoreConcealed = d.bool(forKey: Keys.ignoreConcealed)
        ignoredSourceAppBundleIDs = (d.stringArray(forKey: Keys.ignoredSourceAppBundleIDs) ?? [])
            .filter { !$0.isEmpty }
        barHeight = d.double(forKey: Keys.barHeight)
        showMenuBarIcon = d.bool(forKey: Keys.showMenuBarIcon)
        onboarded = d.bool(forKey: Keys.onboarded)
        iCloudSync = d.bool(forKey: Keys.iCloudSync)
        cloudKitSync = d.bool(forKey: Keys.cloudKitSync)
        isLoaded = true
    }

    var hotkeyDisplay: String {
        HotKeyCenter.describe(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    var quickPasteModifierDisplay: String {
        ShortcutModifier(carbonValue: quickPasteModifier)?.symbol ?? "⌘"
    }

    func isIgnoringSourceApp(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return ignoredSourceAppBundleIDs.contains(bundleID)
    }

    func addIgnoredSourceApp(_ bundleID: String) {
        guard !bundleID.isEmpty, !ignoredSourceAppBundleIDs.contains(bundleID) else { return }
        ignoredSourceAppBundleIDs.append(bundleID)
        ignoredSourceAppBundleIDs.sort()
    }

    func removeIgnoredSourceApp(_ bundleID: String) {
        ignoredSourceAppBundleIDs.removeAll { $0 == bundleID }
    }
}
