import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case chineseSimplified = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System Default".localized
        case .english: return "English"
        case .chineseSimplified: return "简体中文"
        }
    }

    var localeCode: String {
        switch self {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            if preferred.hasPrefix("zh") { return "zh-Hans" }
            return "en"
        case .english: return "en"
        case .chineseSimplified: return "zh-Hans"
        }
    }
}
