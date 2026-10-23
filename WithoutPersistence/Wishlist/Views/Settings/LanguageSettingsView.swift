import SwiftUI

struct LanguageSettingsView: View {
    @Environment(AppLanguageSettings.self) private var languageSettings

    private var languageTitle: String {
        switch languageSettings.selectedLanguage {
        case .simplifiedChinese: "语言设置"
        case .traditionalChinese: "語言設定"
        case .english: "Language Settings"
        case .spanish: "Ajustes de idioma"
        case .japanese: "言語設定"
        case .korean: "언어 설정"
        }
    }

    private var languageSectionTitle: String {
        switch languageSettings.selectedLanguage {
        case .simplifiedChinese: "语言"
        case .traditionalChinese: "語言"
        case .english: "Language"
        case .spanish: "Idioma"
        case .japanese: "言語"
        case .korean: "언어"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AppLanguage.options) { language in
                        Button {
                            languageSettings.select(language)
                        } label: {
                            HStack {
                                Text(language.nativeName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if languageSettings.selectedLanguage == language {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(verbatim: languageSectionTitle)
                }
            }
            .navigationTitle(Text(verbatim: languageTitle))
            .navigationBarTitleDisplayMode(.inline)
        }
        // The language picker stays open while its selection changes. Rebuild
        // its navigation chrome too, since SwiftUI may retain the title from
        // the locale that was active when the sheet was first presented.
        .id(languageSettings.identifier)
        .environment(\.locale, languageSettings.locale)
    }
}
