import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(title: String, body: String)] = [
        ("政策说明", "本政策说明行程管家在当前版本中如何收集、使用、保存和保护你的信息。若应用功能或数据处理方式发生变化，我们会更新本政策。"),
        ("我们处理的信息", "注册时你可以提供称呼、邮箱和手机号。云端账号密码由 Supabase 验证，登录状态及有效期保存在本机。你录入的行程、客户和备注信息保存在本机应用数据中；选择云端账号后可上传到对应云端账号。"),
        ("信息用途", "这些信息用于创建和验证账号、维持登录状态，以及提供行程记录、搜索、管理和云端备份功能。应用不会将这些信息用于广告画像。"),
        ("数据保存与安全", "应用使用设备本地数据库保存业务资料；选择云端账号时，应用会将客户、旅行社、行程及相关联系方式、地址、停靠点和费用上传到 Supabase 云端账号。云端数据按登录账号隔离。密码由 Supabase 验证，登录令牌保存在系统钥匙串中。请妥善保管设备并设置设备锁屏密码。"),
        ("网络传输与第三方", "选择云端账号并登录时，应用会通过加密连接将业务数据发送到 Supabase 项目，以便保存到你的账号。飞友航班查询等外部服务只在你主动使用对应功能时接收所需查询信息。应用不会出售或出租你的个人信息。"),
        ("保留与删除", "本地资料保留在设备中；云端资料保留在你的 Supabase 账号中。删除设备上的资料不会自动删除云端副本。删除后通常无法恢复。"),
        ("未成年人", "本应用面向一般用户。未成年人使用本应用前，应取得监护人的同意，并由监护人协助管理个人信息。"),
        ("政策更新", "当应用功能或适用要求发生变化时，我们可能更新本政策。更新版本会在本页面展示，并更新生效日期。"),
        ("联系我们", "如对本政策或个人信息处理有疑问，请通过应用发布者在 App Store 页面提供的联系渠道与我们联系。")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 54, height: 54)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        Text("行程管家隐私政策")
                            .font(.title2.bold())
                        Text("生效日期：2026年10月10日")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 2)

                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LocalizedStringKey(section.title))
                                .font(.headline)
                            Text(LocalizedStringKey(section.body))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Text("本页面为当前应用功能说明；如实际数据处理方式发生变化，请以更新后的政策为准。")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(20)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("隐私政策")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
