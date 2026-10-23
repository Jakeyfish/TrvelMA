import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case spanish = "es"
    case japanese = "ja"
    case korean = "ko"

    /// Keep the order and available choices explicit so Simplified Chinese is
    /// always included in the in-app language picker.
    static let options: [AppLanguage] = [
        .simplifiedChinese,
        .traditionalChinese,
        .english,
        .spanish,
        .japanese,
        .korean
    ]

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .spanish: "Español"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }
}

extension AppLanguageSettings {
    /// An explicit in-app choice wins. Until the user chooses one, follow the
    /// device language so manually localized strings and SwiftUI `Text` agree.
    static var effectiveIdentifier: String {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let language = AppLanguage(rawValue: saved) {
            return language.rawValue
        }

        let preferredIdentifier = Locale.preferredLanguages.first ?? Locale.current.identifier
        let preferredLocale = Locale(identifier: preferredIdentifier)
        let languageCode = preferredLocale.language.languageCode?.identifier.lowercased() ?? ""
        if languageCode == "zh" {
            let scriptCode = preferredLocale.language.script?.identifier.lowercased() ?? ""
            let regionCode = preferredLocale.region?.identifier.lowercased() ?? ""
            return scriptCode == "hant" || ["tw", "hk", "mo"].contains(regionCode)
                ? AppLanguage.traditionalChinese.rawValue
                : AppLanguage.simplifiedChinese.rawValue
        }
        if let language = AppLanguage(rawValue: languageCode) {
            return language.rawValue
        }
        return AppLanguage.simplifiedChinese.rawValue
    }

    static var currentLocale: Locale {
        Locale(identifier: effectiveIdentifier)
    }
}

@Observable
final class AppLanguageSettings {
    private let defaultsKey = "appLanguage"

    var identifier: String {
        didSet { UserDefaults.standard.set(identifier, forKey: defaultsKey) }
    }

    init() {
        identifier = Self.effectiveIdentifier
    }

    var locale: Locale { Locale(identifier: identifier) }

    var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: identifier) ?? .simplifiedChinese
    }

    func select(_ language: AppLanguage) {
        identifier = language.rawValue
    }
}
