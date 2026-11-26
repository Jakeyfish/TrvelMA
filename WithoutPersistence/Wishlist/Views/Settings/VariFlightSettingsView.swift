import SwiftUI

struct VariFlightSettingsView: View {
    @Environment(AuthViewModel.self) private var auth

    @State private var values = SupabaseAuthClient.FlightAutoPreferences(international: 60, domestic: 40, followup: 3)
    @State private var loaded = false
    @State private var busy = false
    @State private var error = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if auth.canQueryFlights {
                        Label("云端安全查询", systemImage: "lock.shield")
                        Text("云端航班查询由服务器安全代理处理，不会把共享飞友密钥发送到此设备。")
                    } else {
                        Text("在线航班查询仅限云端版。")
                        Text("本地版可手动填写航班信息，并查看已保存的航班资料。")
                    }
                }
                if auth.canQueryFlights {
                    if BillingReleaseConfiguration.salesEnabled {
                        Section {
                            NavigationLink { FlightBeanWalletView() } label: {
                                HStack { SilverBeanIcon(); Text("云豆余额") }
                            }
                        }
                    }
                    Section {
                        Group {
                            minutesField("国际航班首查", value: $values.international)
                            minutesField("国内航班首查", value: $values.domestic)
                            minutesField("落地复查", value: $values.followup)
                        }
                        .disabled(!loaded || busy)
                        Button("保存设置") { Task { await update(saving: values) } }
                            .disabled(!loaded || busy || !validMinutes)
                        if error {
                            Text("自动读取设置暂不可用，请重试。")
                                .font(.footnote).foregroundStyle(.secondary)
                            if !loaded { Button("重试") { Task { await update() } } }
                        }
                    } header: {
                        Text("自动读取时间（分钟）")
                    } footer: {
                        Text("首查按计划落地时间提前读取；复查按最新预计落地时间延后读取一次。")
                    }
                }
                Section {
                    Text("查询失败或没有返回航站楼、行李转盘时，请以航空公司或机场信息为准。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .task(id: "\(auth.currentEmail)-\(auth.canQueryFlights)") {
                values = .init(international: 60, domestic: 40, followup: 3)
                busy = false
                loaded = false
                error = false
                if auth.canQueryFlights { await update() }
            }
            .navigationTitle("航班查询设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var validMinutes: Bool {
        [values.international, values.domestic, values.followup].allSatisfy { (0...360).contains($0) }
    }

    private func minutesField(_ label: LocalizedStringKey, value: Binding<Int>) -> some View {
        LabeledContent {
            TextField(label, value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
        } label: {
            Text(label)
        }
    }

    private func update(saving valuesToSave: SupabaseAuthClient.FlightAutoPreferences? = nil) async {
        guard let token = auth.cloudAccessToken else { error = true; return }
        let email = auth.currentEmail
        busy = true
        defer { if auth.currentEmail == email { busy = false } }
        do {
            let saved = try await SupabaseAuthClient.flightAutoPreferences(accessToken: token, saving: valuesToSave)
            guard !Task.isCancelled, auth.currentEmail == email else { return }
            values = saved
            loaded = true
            error = false
        } catch {
            guard !Task.isCancelled, auth.currentEmail == email else { return }
            self.error = true
        }
    }
}
