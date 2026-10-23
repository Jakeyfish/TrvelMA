import SwiftUI

struct VariFlightSettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var apiKey = VariFlightAPIKeyStore.read() ?? ""
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if auth.isCloudAccount {
                    Section {
                        Label("云端安全查询", systemImage: "lock.shield")
                        Text("云端航班查询由服务器安全代理处理，不会把共享飞友密钥发送到此设备。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        SecureField("API 密钥", text: $apiKey)
                            .keyboardDoneToolbar()
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } header: {
                        Text("飞友 AI 开放平台")
                    } footer: {
                        Text("本地版查询使用你自己的密钥。密钥只保存在本机钥匙串。")
                    }

                    Section {
                        Button {
                            saveAPIKey()
                        } label: {
                            Label("保存密钥", systemImage: "key.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Section {
                        Button(role: .destructive) {
                            deleteAPIKey()
                        } label: {
                            Label("删除密钥", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .disabled(apiKey.isEmpty)
                    }
                }

                Section {
                    Link(destination: URL(string: "https://ai.variflight.com/keys")!) {
                        Label("打开飞友密钥管理", systemImage: "key.horizontal")
                    }
                    Link(destination: URL(string: "https://ai.variflight.com/zh/docs/aviation")!) {
                        Label("查看接口说明", systemImage: "doc.text")
                    }
                }

                Section {
                    Text("查询失败或没有返回航站楼、行李转盘时，请以航空公司或机场信息为准。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("航班查询设置")
            .navigationBarTitleDisplayMode(.inline)
            .alert("飞友航班查询", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("确定", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func saveAPIKey() {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            try VariFlightAPIKeyStore.save(value)
            apiKey = value
            alertMessage = "API 密钥已保存到本机钥匙串。"
        } catch {
            alertMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func deleteAPIKey() {
        VariFlightAPIKeyStore.delete()
        apiKey = ""
        alertMessage = "API 密钥已删除。"
    }
}
