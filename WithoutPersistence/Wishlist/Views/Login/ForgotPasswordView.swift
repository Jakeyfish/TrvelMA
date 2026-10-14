import SwiftUI
import SwiftData

struct ForgotPasswordView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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
                    HStack {
                        TextField("验证码", text: $verificationCode)
                            .keyboardType(.numberPad)
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

                if let message {
                    Section {
                        Text(LocalizedStringKey(message))
                            .font(.footnote)
                            .foregroundStyle(isError ? Color.red : Color.secondary)
                    }
                } else if isShowingCodeNotice {
                    Section {
                        Text("演示模式验证码：\(auth.demoVerificationCode)（尚未接入短信/邮件发送）")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("重置密码") { resetPassword() }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .disabled(!codeRequested)
                }
            }
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
}
