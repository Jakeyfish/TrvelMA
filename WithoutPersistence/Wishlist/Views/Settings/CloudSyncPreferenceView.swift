import SwiftUI

struct CloudSyncPreferenceView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var selection: CloudLocalDataPreference = .syncLocalData

    var body: some View {
        NavigationStack {
            List {
                Section {
                    preferenceRow(
                        .syncLocalData,
                        title: "同步本机资料",
                        detail: "登录此云端账号时，自动将本机客户、旅行社、行程和名片资料同步到云端。"
                    )
                    preferenceRow(
                        .cloudDataOnly,
                        title: "仅使用云端资料",
                        detail: "本机资料留在设备上；登录后只同步此云端账号已有的资料。"
                    )
                } header: {
                    Text("默认同步方式")
                } footer: {
                    Text("此偏好仅适用于当前云端账号。更改后，下次登录时生效。")
                }

                Section {
                    Button("保存设置") {
                        selection.save(for: auth.currentEmail)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fontWeight(.semibold)
                }
            }
            .navigationTitle("数据同步设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                selection = CloudLocalDataPreference.load(for: auth.currentEmail) ?? .syncLocalData
            }
        }
    }

    private func preferenceRow(_ preference: CloudLocalDataPreference, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        Button {
            selection = preference
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selection == preference ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selection == preference ? Color.accentColor : Color.secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
