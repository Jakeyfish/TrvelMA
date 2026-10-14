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

@Observable
final class AppLanguageSettings {
    private let defaultsKey = "appLanguage"

    var identifier: String {
        didSet { UserDefaults.standard.set(identifier, forKey: defaultsKey) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: defaultsKey)
        identifier = AppLanguage(rawValue: saved ?? "")?.rawValue ?? AppLanguage.simplifiedChinese.rawValue
    }

    var locale: Locale { Locale(identifier: identifier) }

    var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: identifier) ?? .simplifiedChinese
    }

    func select(_ language: AppLanguage) {
        identifier = language.rawValue
    }
}
