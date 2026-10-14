import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(title: String, body: String)] = [
        ("政策说明", "本政策说明行程管家在当前版本中如何收集、使用、保存和保护你的信息。若应用功能或数据处理方式发生变化，我们会更新本政策。"),
        ("我们处理的信息", "注册时你可以提供称呼、邮箱和手机号。密码通过设备钥匙串保存。登录状态及有效期保存在本机。你录入的行程、客户和备注信息保存在本机应用数据中。"),
        ("信息用途", "这些信息用于创建和验证本地账号、维持登录状态，以及提供行程记录、搜索和管理功能。应用不会将这些信息用于广告画像。"),
        ("本地保存与安全", "当前版本使用设备本地数据库保存账号资料和行程数据，并使用系统钥匙串保存密码。请妥善保管设备并设置设备锁屏密码。卸载应用、清除应用数据或更换设备可能导致本地资料无法恢复。"),
        ("网络传输与第三方", "当前版本未提供云端账号同步功能。除非你主动使用设备系统提供的功能，本应用不会主动把上述资料发送给云盛科技服务器，也不会出售或出租你的个人信息。未来接入云服务或第三方功能时，我们会更新本政策并说明相关处理方式。"),
        ("保留与删除", "本地资料会保留在设备中，直到你在应用或设备中删除相关资料，或卸载应用。你可以通过设备设置管理应用数据；删除后通常无法恢复。"),
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
