import Foundation
import Observation

@Observable
final class LocalizationManager {
    nonisolated(unsafe) static let shared = LocalizationManager()

    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            loadTranslations()
        }
    }

    @ObservationIgnored private var translations: [String: String] = [:]

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        language = AppLanguage(rawValue: saved) ?? .system
        loadTranslations()
    }

    private func loadTranslations() {
        let code = language.localeCode
        translations = Self.loadStrings(for: code) ?? Self.loadStrings(for: "en") ?? [:]
    }

    private static func loadStrings(for code: String) -> [String: String]? {
        if let lproj = Bundle.main.path(forResource: code, ofType: "lproj") {
            let path = (lproj as NSString).appendingPathComponent("Localizable.strings")
            if let dict = NSDictionary(contentsOfFile: path) as? [String: String] {
                return dict
            }
        }
        if let resourceURL = Bundle.module.resourceURL {
            let candidates = [
                resourceURL.appendingPathComponent("Resources/\(code).lproj/Localizable.strings"),
                resourceURL.appendingPathComponent("\(code).lproj/Localizable.strings"),
            ]
            for url in candidates {
                if let dict = NSDictionary(contentsOf: url) as? [String: String] {
                    return dict
                }
            }
        }
        return nil
    }

    func t(_ key: String) -> String {
        let _ = language
        return translations[key] ?? key
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}

extension String {
    var localized: String {
        LocalizationManager.shared.t(self)
    }
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: key.localized, arguments: args)
}
