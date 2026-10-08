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

enum HistoryRetentionMode: String, CaseIterable, Identifiable {
    case itemCount
    case timeInterval

    var id: String { rawValue }

    var title: String {
        switch self {
        case .itemCount: return "Number of clips"
        case .timeInterval: return "Age of clips"
        }
    }
}

/// The discrete stops on the time-based retention slider. `historyRetentionDays`
/// stays the underlying source of truth (a raw day count, with 0 meaning
/// "forever" - never prune by age) - this just names the stops so the slider
/// can snap between them instead of offering a raw number field.
enum HistoryRetentionPreset: Int, CaseIterable, Identifiable {
    case day
    case week
    case twoWeeks
    case threeWeeks
    case month
    case twoMonths
    case threeMonths
    case sixMonths
    case year
    case forever

    var id: Int { rawValue }

    /// 0 means forever - no automatic time-based pruning.
    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .twoWeeks: return 14
        case .threeWeeks: return 21
        case .month: return 30
        case .twoMonths: return 60
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .year: return 365
        case .forever: return 0
        }
    }

    var title: String {
        switch self {
        case .day: return "1 Day"
        case .week: return "1 Week"
        case .twoWeeks: return "2 Weeks"
        case .threeWeeks: return "3 Weeks"
        case .month: return "1 Month"
        case .twoMonths: return "2 Months"
        case .threeMonths: return "3 Months"
        case .sixMonths: return "6 Months"
        case .year: return "1 Year"
        case .forever: return "Forever"
        }
    }

    var shortTitle: String {
        switch self {
        case .day: return "1d"
        case .week: return "1w"
        case .twoWeeks: return "2w"
        case .threeWeeks: return "3w"
        case .month: return "1m"
        case .twoMonths: return "2m"
        case .threeMonths: return "3m"
        case .sixMonths: return "6m"
        case .year: return "1y"
        case .forever: return "∞"
        }
    }

    var sliderIndex: Double { Double(rawValue) }

    /// Snaps an arbitrary day count (including ones from before this preset
    /// set existed) to its nearest stop, so old UserDefaults values still
    /// land on a sensible position on the slider.
    init(nearestDays days: Int) {
        self = Self.allCases.min(by: { abs($0.days - days) < abs($1.days - days) }) ?? .month
    }

    init(sliderIndex: Double) {
        let index = min(Self.allCases.count - 1, max(0, Int(sliderIndex.rounded())))
        self = Self.allCases[index]
    }
}

enum ClipColorTheme: Int, CaseIterable, Identifiable {
    case `default`
    case vibrant
    case accentShades

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .default: "Default"
        case .vibrant: "Vibrant"
        case .accentShades: "Accent shades"
        }
    }

    var detail: String {
        switch self {
        case .default:
            "Match each clip to its source app\u{2019}s familiar card color."
        case .vibrant:
            "Use a stronger, higher-contrast version of each source app color."
        case .accentShades:
            "Give each source app a stable lighter or darker shade of one color."
        }
    }
}

enum SelectedClipPosition: Int, CaseIterable, Identifiable {
    case center
    case rightEdge

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .center: "Center"
        case .rightEdge: "Right edge"
        }
    }

    var detail: String {
        switch self {
        case .center: "Keep the selected clip centered with surrounding context visible."
        case .rightEdge: "Place the selected clip at the far right, like Paste."
        }
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
        static let historyRetentionMode = "historyRetentionMode"
        static let historyRetentionDays = "historyRetentionDays"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let quickPasteModifier = "quickPasteModifier"
        static let plainTextModifier = "plainTextModifier"
        static let launchAtLogin = "launchAtLogin"
        static let hideOnClickOutside = "hideOnClickOutside"
        static let pasteDirectly = "pasteDirectly"
        static let playSound = "playSound"
        static let playSoundOnCopy = "playSoundOnCopy"
        static let ignoreConcealed = "ignoreConcealed"
        static let ignoredSourceAppBundleIDs = "ignoredSourceAppBundleIDs"
        static let barHeight = "barHeight"
        static let showBarResizeHandle = "showBarResizeHandle"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let onboarded = "onboarded"
        static let iCloudSync = "iCloudSync"
        static let cloudKitSync = "cloudKitSync"
        static let clipColorTheme = "clipColorTheme"
        static let clipColorAccentHex = "clipColorAccentHex"
        static let selectedClipPosition = "selectedClipPosition"
    }

    var historyLimit: Int {
        didSet {
            guard isLoaded else { return }
            if historyLimit < 20 { historyLimit = 20; return }
            d.set(historyLimit, forKey: Keys.historyLimit)
        }
    }

    var historyRetentionMode: HistoryRetentionMode {
        didSet {
            guard isLoaded else { return }
            d.set(historyRetentionMode.rawValue, forKey: Keys.historyRetentionMode)
        }
    }

    /// A raw day count for time-based pruning; 0 means forever (no automatic
    /// pruning by age). See `HistoryRetentionPreset` for the named stops the
    /// Settings slider snaps this to.
    var historyRetentionDays: Int {
        didSet {
            guard isLoaded else { return }
            if historyRetentionDays < 0 { historyRetentionDays = 0; return }
            d.set(historyRetentionDays, forKey: Keys.historyRetentionDays)
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

    var playSoundOnCopy: Bool {
        didSet { guard isLoaded else { return }; d.set(playSoundOnCopy, forKey: Keys.playSoundOnCopy) }
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
            let normalized = BarResizeGeometry.normalizedPersistedHeight(barHeight)
            if normalized != barHeight { barHeight = normalized; return }
            d.set(barHeight, forKey: Keys.barHeight)
        }
    }

    var showBarResizeHandle: Bool {
        didSet {
            guard isLoaded else { return }
            d.set(showBarResizeHandle, forKey: Keys.showBarResizeHandle)
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

    var clipColorTheme: ClipColorTheme {
        didSet { guard isLoaded else { return }; d.set(clipColorTheme.rawValue, forKey: Keys.clipColorTheme) }
    }

    var clipColorAccentHex: String {
        didSet { guard isLoaded else { return }; d.set(clipColorAccentHex, forKey: Keys.clipColorAccentHex) }
    }

    var selectedClipPosition: SelectedClipPosition {
        didSet { guard isLoaded else { return }; d.set(selectedClipPosition.rawValue, forKey: Keys.selectedClipPosition) }
    }

    private init() {
        d.register(defaults: [
            Keys.historyLimit: 500,
            Keys.historyRetentionMode: HistoryRetentionMode.itemCount.rawValue,
            Keys.historyRetentionDays: 30,
            Keys.hotkeyKeyCode: kVK_ANSI_V,
            Keys.hotkeyModifiers: cmdKey | shiftKey,
            Keys.quickPasteModifier: cmdKey,
            Keys.plainTextModifier: shiftKey,
            Keys.launchAtLogin: false,
            Keys.hideOnClickOutside: true,
            Keys.pasteDirectly: true,
            Keys.playSound: false,
            // Off by default, matching the paste sound: existing users
            // shouldn't gain a new audible behavior from an update.
            Keys.playSoundOnCopy: false,
            Keys.ignoreConcealed: true,
            Keys.ignoredSourceAppBundleIDs: [],
            Keys.barHeight: BarResizeGeometry.defaultHeight,
            Keys.showBarResizeHandle: false,
            Keys.showMenuBarIcon: true,
            Keys.onboarded: false,
            Keys.iCloudSync: false,
            Keys.cloudKitSync: true,
            Keys.clipColorTheme: ClipColorTheme.default.rawValue,
            Keys.clipColorAccentHex: "#FF5A9F",
            Keys.selectedClipPosition: SelectedClipPosition.center.rawValue
        ])
        historyLimit = d.integer(forKey: Keys.historyLimit)
        historyRetentionMode = HistoryRetentionMode(rawValue: d.string(forKey: Keys.historyRetentionMode) ?? "")
            ?? .itemCount
        historyRetentionDays = max(0, d.integer(forKey: Keys.historyRetentionDays))
        hotkeyKeyCode = d.integer(forKey: Keys.hotkeyKeyCode)
        hotkeyModifiers = d.integer(forKey: Keys.hotkeyModifiers)
        quickPasteModifier = d.integer(forKey: Keys.quickPasteModifier)
        plainTextModifier = d.integer(forKey: Keys.plainTextModifier)
        launchAtLogin = d.bool(forKey: Keys.launchAtLogin)
        hideOnClickOutside = d.bool(forKey: Keys.hideOnClickOutside)
        pasteDirectly = d.bool(forKey: Keys.pasteDirectly)
        playSound = d.bool(forKey: Keys.playSound)
        playSoundOnCopy = d.bool(forKey: Keys.playSoundOnCopy)
        ignoreConcealed = d.bool(forKey: Keys.ignoreConcealed)
        ignoredSourceAppBundleIDs = (d.stringArray(forKey: Keys.ignoredSourceAppBundleIDs) ?? [])
            .filter { !$0.isEmpty }
        let storedBarHeight = d.double(forKey: Keys.barHeight)
        let normalizedBarHeight = BarResizeGeometry.normalizedPersistedHeight(storedBarHeight)
        barHeight = normalizedBarHeight
        showBarResizeHandle = d.bool(forKey: Keys.showBarResizeHandle)
        showMenuBarIcon = d.bool(forKey: Keys.showMenuBarIcon)
        onboarded = d.bool(forKey: Keys.onboarded)
        iCloudSync = d.bool(forKey: Keys.iCloudSync)
        cloudKitSync = d.bool(forKey: Keys.cloudKitSync)
        clipColorTheme = ClipColorTheme(rawValue: d.integer(forKey: Keys.clipColorTheme)) ?? .default
        clipColorAccentHex = d.string(forKey: Keys.clipColorAccentHex) ?? "#FF5A9F"
        selectedClipPosition = SelectedClipPosition(rawValue: d.integer(forKey: Keys.selectedClipPosition)) ?? .center
        isLoaded = true
        if normalizedBarHeight != storedBarHeight {
            d.set(normalizedBarHeight, forKey: Keys.barHeight)
        }
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
