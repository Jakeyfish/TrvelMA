import SwiftUI

struct LanguageSettingsView: View {
    @Environment(AppLanguageSettings.self) private var languageSettings

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
                    Text("语言")
                }
            }
            .navigationTitle("语言设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
