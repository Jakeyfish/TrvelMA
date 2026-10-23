import SwiftUI
import SwiftData
import UIKit

struct RegisterView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("auth.accountMode.cloud") private var useCloudAccount = false

    @State private var email = ""
    @State private var salutation = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var verificationCode = ""
    @State private var isPasswordVisible = false
    @State private var codeRequested = false
    @State private var isShowingCodeNotice = false
    @State private var message: String?
    @State private var isError = true
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SystemIMETextField(text: $salutation, placeholder: "称呼")
                        .frame(minHeight: 22)
                    TextField("邮箱", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SystemIMETextField(
                        text: $phone,
                        placeholder: "手机号",
                        keyboardType: .phonePad,
                        textContentType: .telephoneNumber
                    )
                }

                Section {
                    passwordField(title: "密码", value: $password)
                    passwordField(title: "检验密码", value: $confirmPassword)
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

                Section {
                    Button("提交") { submit() }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .disabled(isSubmitting)
                }
            }
            .keyboardDoneToolbar()
            .navigationTitle("用户注册")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func passwordField(title: String, value: Binding<String>) -> some View {
        HStack {
            Group {
                if isPasswordVisible {
                    TextField(LocalizedStringKey(title), text: value)
                } else {
                    SecureField(title, text: value)
                }
            }
            .textContentType(.newPassword)
            Button {
                isPasswordVisible.toggle()
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(isPasswordVisible ? "隐藏密码" : "显示密码")
        }
    }

    private func submit() {
        isShowingCodeNotice = false
        guard password == confirmPassword else {
            isError = true
            message = "两次输入的密码不一致。"
            return
        }
        isSubmitting = true
        Task {
            let error: String?
            if useCloudAccount {
                error = await auth.registerCloud(email: email, salutation: salutation, phone: phone, password: password)
            } else {
                error = auth.register(email: email, salutation: salutation, phone: phone, password: password, context: modelContext)
            }
            isSubmitting = false
            if let error {
                if useCloudAccount && error.hasPrefix(String(localized: "注册成功。", locale: AppLanguageSettings.currentLocale)) {
                    isError = false
                    message = error
                } else {
                    isError = true
                    message = error
                }
            } else {
                dismiss()
            }
        }
    }
}

#Preview {
    @Previewable @State var auth = AuthViewModel()
    RegisterView().environment(auth)
}
