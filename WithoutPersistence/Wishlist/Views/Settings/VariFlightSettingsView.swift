import SwiftUI

struct VariFlightSettingsView: View {
    @Environment(AuthViewModel.self) private var auth

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
                Section {
                    Text("查询失败或没有返回航站楼、行李转盘时，请以航空公司或机场信息为准。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("航班查询设置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
