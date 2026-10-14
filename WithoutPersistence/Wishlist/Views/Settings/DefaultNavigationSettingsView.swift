import SwiftUI

struct DefaultNavigationSettingsView: View {
    @AppStorage(NavigationProvider.defaultsKey) private var selectedProvider = NavigationProvider.appleMaps.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(NavigationProvider.allCases) { provider in
                        Button {
                            selectedProvider = provider.rawValue
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: provider.symbol)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 24)
                                Text(LocalizedStringKey(provider.title))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selectedProvider == provider.rawValue {
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
                    Text("默认导航应用")
                } footer: {
                    Text("行程起始点、目的地和客户常用地址都会使用此应用规划驾车路线。")
                }
            }
            .navigationTitle("默认导航")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
