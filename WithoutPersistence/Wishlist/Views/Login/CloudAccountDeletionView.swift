import SwiftUI
import SwiftData

struct CloudAccountDeletionView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var deleting = false
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("永久删除云端账号") {
                    Text(auth.currentEmail)
                    Text("将永久删除此云端账号、客户、行程、旅行社、财务记录、名片图片及关联资料，无法恢复。其他账号不受影响。")
                    Text("删除账号不会自动取消 Apple 订阅，请先在系统订阅管理中取消续费。").foregroundStyle(.secondary)
                    Link("管理 Apple 订阅", destination: URL(string: "https://apps.apple.com/account/subscriptions/")!)
                }
                Section("确认身份") {
                    SecureField("当前密码", text: $password).textContentType(.password)
                    TextField("输入 DELETE 确认", text: $confirmation).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                    if deleting { ProgressView("正在删除，请勿关闭…") }
                    Button("永久删除此云端账号", role: .destructive) { Task { await remove() } }
                        .disabled(deleting || password.isEmpty || confirmation != "DELETE" || auth.isCloudSyncInProgress)
                }
            }
            .navigationTitle("删除云端账号")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(deleting) } }
            .interactiveDismissDisabled(deleting)
        }
    }

    @MainActor private func remove() async {
        guard !deleting, confirmation == "DELETE", !auth.isCloudSyncInProgress else { return }
        deleting = true; error = ""
        let email = auth.currentEmail
        defer { password = ""; deleting = false }
        do {
            guard let token = await auth.refreshCloudAccessToken() else { error = AppLocalization.text("请退出并重新登录后再试。"); return }
            try await SupabaseAuthClient.deleteCloudAccount(accessToken: token, password: password)
            guard auth.currentEmail == email else { dismiss(); return }
            // The server confirmed deletion first. Local cleanup never runs on a failed request.
            try? auth.clearCurrentCloudAccountLocalData(context: context)
            auth.logout()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
