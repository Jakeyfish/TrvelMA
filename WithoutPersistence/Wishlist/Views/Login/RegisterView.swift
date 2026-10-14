import SwiftUI
import SwiftData
import UIKit

struct RegisterView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

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
                    TextField("手机号", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }

                Section {
                    passwordField(title: "密码", value: $password)
                    passwordField(title: "检验密码", value: $confirmPassword)
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
                    Button("提交") { submit() }
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
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
        if let error = auth.register(email: email, salutation: salutation, phone: phone, password: password, context: modelContext) {
            isError = true
            message = error
        } else {
            dismiss()
        }
    }
}

#Preview {
    @Previewable @State var auth = AuthViewModel()
    RegisterView().environment(auth)
}
/// A system UITextField for short text that preserves active Chinese IME composition.
struct SystemIMETextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.keyboardType = .default
        field.autocapitalizationType = .sentences
        field.autocorrectionType = .default
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        field.accessibilityLabel = placeholder
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        field.placeholder = placeholder
        // Do not overwrite pinyin/Wubi marked text while the user is composing.
        guard field.markedTextRange == nil, field.text != text else { return }
        field.text = text
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        @objc func editingChanged(_ field: UITextField) {
            updateBinding(from: field)
        }

        func textFieldDidChangeSelection(_ field: UITextField) {
            updateBinding(from: field)
        }

        private func updateBinding(from field: UITextField) {
            guard field.markedTextRange == nil else { return }
            let value = field.text ?? ""
            if text.wrappedValue != value {
                text.wrappedValue = value
            }
        }
    }
}
