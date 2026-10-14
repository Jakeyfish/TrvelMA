import SwiftUI

struct FlightAwareSettingsView: View {
    @State private var apiKey = FlightAwareAPIKeyStore.read() ?? ""
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("API 密钥", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    HStack {
                        Button("保存密钥") {
                            do {
                                try FlightAwareAPIKeyStore.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                                alertMessage = "API 密钥已保存到本机钥匙串。"
                            } catch {
                                alertMessage = "保存失败：\(error.localizedDescription)"
                            }
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                        Button("删除密钥", role: .destructive) {
                            FlightAwareAPIKeyStore.delete()
                            apiKey = ""
                            alertMessage = "API 密钥已删除。"
                        }
                        .disabled(apiKey.isEmpty)
                    }
                } header: {
                    Text("FlightAware AeroAPI")
                } footer: {
                    Text("查询航班时会使用此密钥。航班时间按出发地或到达地的当地时区显示；航站楼和行李转盘仅在 FlightAware 有提供时显示。")
                }

                Section {
                    Text("密钥保存在本机钥匙串。若将来公开发布应用，建议通过服务器代理请求，避免在客户端使用 API 密钥。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("航班查询设置")
            .navigationBarTitleDisplayMode(.inline)
            .alert("FlightAware", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("确定", role: .cancel) { alertMessage = nil }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }
}
