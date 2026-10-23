import SwiftUI
import SwiftData

struct ForgotPasswordView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("auth.accountMode.cloud") private var useCloudAccount = false

    @State private var email = ""
    @State private var verificationCode = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var codeRequested = false
    @State private var isShowingCodeNotice = false
    @State private var message: String?
    @State private var isError = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("邮箱", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if useCloudAccount {
                        Button("发送云端重置邮件") { sendCloudRecovery() }
                    } else {
                        HStack {
                            SystemIMETextField(
                                text: $verificationCode,
                                placeholder: "验证码",
                                keyboardType: .numberPad,
                                textContentType: .oneTimeCode,
                                clearsZeroOnFocus: false
                            )
                            Button {
                                codeRequested = true
                                isError = false
                                message = nil
                                isShowingCodeNotice = true
                            } label: {
                                Text(LocalizedStringKey(codeRequested ? "重新获取" : "获取验证码"))
                            }
                        }
                        SecureField("新密码（至少 6 位）", text: $newPassword)
                            .textContentType(.newPassword)
                        SecureField("确认新密码", text: $confirmPassword)
                            .textContentType(.newPassword)
                    }
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(isError ? Color.red : Color.secondary)
                    }
                } else if isShowingCodeNotice {
                    Section {
                        Text(String(format: String(localized: "演示模式验证码：%@（尚未接入短信/邮件发送）", locale: AppLanguageSettings.currentLocale), locale: AppLanguageSettings.currentLocale, arguments: [auth.demoVerificationCode]))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !useCloudAccount {
                    Section {
                        Button("重置密码") { resetPassword() }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .disabled(!codeRequested)
                    }
                }
            }
            .keyboardDoneToolbar()
            .navigationTitle("忘记密码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func resetPassword() {
        isShowingCodeNotice = false
        guard newPassword == confirmPassword else {
            isError = true
            message = "两次输入的新密码不一致。"
            return
        }
        guard codeRequested else {
            isError = true
            message = "请先获取验证码。"
            return
        }
        if let error = auth.resetPassword(email: email, verificationCode: verificationCode, newPassword: newPassword, context: modelContext) {
            isError = true
            message = error
        } else {
            dismiss()
        }
    }

    private func sendCloudRecovery() {
        isError = false
        message = "正在发送重置邮件…"
        Task {
            if let error = await auth.sendCloudPasswordRecovery(email: email) {
                isError = true
                message = error
            } else {
                isError = false
                message = "如果该邮箱已注册，Supabase 会发送密码重置邮件。请按邮件提示完成重置。"
            }
        }
    }
}
