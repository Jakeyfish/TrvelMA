import SwiftUI
import SwiftData

struct LoginView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("auth.rememberEmail") private var rememberEmail = false
    @AppStorage("auth.rememberedEmail") private var rememberedEmail = ""
    @AppStorage("auth.accountMode.cloud") private var useCloudAccount = false
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var showRegister = false
    @State private var showForgotPassword = false
    @State private var errorMessage: String?
    @State private var isSigningIn = false

    private var isDarkMode: Bool { colorScheme == .dark }
    private var pageGradient: [Color] {
        isDarkMode
            ? [Color(red: 0.035, green: 0.11, blue: 0.23), Color(red: 0.055, green: 0.24, blue: 0.43), Color(red: 0.08, green: 0.35, blue: 0.52)]
            : [Color(red: 0.89, green: 0.94, blue: 1.0), Color(red: 0.94, green: 0.97, blue: 1.0), Color(red: 0.84, green: 0.92, blue: 0.98)]
    }
    private var primaryText: Color { isDarkMode ? .white : Color(red: 0.08, green: 0.14, blue: 0.24) }
    private var secondaryText: Color { isDarkMode ? .white.opacity(0.72) : Color(red: 0.30, green: 0.38, blue: 0.49) }
    private var fieldFill: Color { isDarkMode ? .white.opacity(0.10) : .white.opacity(0.78) }
    private var fieldBorder: Color { isDarkMode ? .white.opacity(0.18) : Color.black.opacity(0.08) }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: pageGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill(Color.cyan.opacity(isDarkMode ? 0.18 : 0.10))
                    .frame(width: 280, height: 280)
                    .blur(radius: 70)
                    .offset(x: 150, y: -300)

                Circle()
                    .fill(Color.blue.opacity(isDarkMode ? 0.22 : 0.08))
                    .frame(width: 260, height: 260)
                    .blur(radius: 75)
                    .offset(x: -160, y: 300)

                VStack(spacing: 24) {
                    Spacer(minLength: 24)

                    Image("BrandLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 92, height: 92)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(fieldBorder, lineWidth: 1))
                        .shadow(color: .black.opacity(0.18), radius: 16, y: 7)

                    VStack(spacing: 8) {
                        Text("行程管家")
                            .font(.largeTitle.bold())
                            .foregroundStyle(primaryText)
                        Text("云盛科技")
                            .font(.caption.weight(.semibold))
                            .tracking(3)
                            .foregroundStyle(.cyan.opacity(0.92))
                        Text("登录后管理你的行程")
                            .foregroundStyle(secondaryText)
                    }

                    VStack(spacing: 16) {
                        Picker("账号类型", selection: $useCloudAccount) {
                            Text("本地账号").tag(false)
                            Text("云端账号").tag(true)
                        }
                        .pickerStyle(.segmented)

                        TextField("邮箱", text: $email)
                            .keyboardDoneToolbar()
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(primaryText)
                            .tint(.cyan)
                            .padding(16)
                            .background(fieldFill, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(fieldBorder, lineWidth: 1))

                        HStack(spacing: 10) {
                            Group {
                                if isPasswordVisible {
                                    TextField("密码", text: $password)
                                        .keyboardDoneToolbar()
                                } else {
                                    SecureField("密码", text: $password)
                                        .keyboardDoneToolbar()
                                }
                            }
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(primaryText)
                            .tint(.cyan)

                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(secondaryText)
                            }
                            .accessibilityLabel(isPasswordVisible ? "隐藏密码" : "显示密码")
                        }
                        .padding(16)
                        .background(fieldFill, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(fieldBorder, lineWidth: 1))

                        Toggle("记住邮箱", isOn: $rememberEmail)
                            .font(.subheadline)
                            .foregroundStyle(primaryText.opacity(0.92))
                            .tint(.cyan)
                            .onChange(of: rememberEmail) { _, isRemembered in
                                if !isRemembered {
                                    rememberedEmail = ""
                                }
                            }
                    }
                    .padding(20)
                    .background(isDarkMode ? Color.white.opacity(0.07) : Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(fieldBorder.opacity(0.8), lineWidth: 1))

                    if let errorMessage {
                        Text(LocalizedStringKey(errorMessage))
                            .font(.footnote)
                            .foregroundStyle(isDarkMode ? Color(red: 1, green: 0.72, blue: 0.72) : Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        if useCloudAccount {
                            isSigningIn = true
                            Task {
                                errorMessage = await auth.loginToCloud(email: email, password: password)
                                finishLoginIfNeeded()
                                isSigningIn = false
                            }
                        } else {
                            errorMessage = auth.login(email: email, password: password, context: modelContext)
                            finishLoginIfNeeded()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isSigningIn { ProgressView().tint(Color(red: 0.035, green: 0.17, blue: 0.32)) }
                            Text("登录")
                        }
                            .font(.headline)
                            .foregroundStyle(Color(red: 0.035, green: 0.17, blue: 0.32))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 15))
                    }
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.16), radius: 14, y: 7)
                    .disabled(isSigningIn)

                    HStack {
                        Button("忘记密码？") { showForgotPassword = true }
                        Spacer()
                        Button("注册账号") { showRegister = true }
                    }
                    .font(.subheadline.weight(.medium))
                    .tint(isDarkMode ? .white : Color.accentColor)

                    Spacer(minLength: 24)
                    Text(useCloudAccount ? "云端资料会同步到当前账号；首次同步前会询问是否上传本机资料" : "本机资料只保存在此设备，不会自动上传")
                        .font(.caption)
                        .foregroundStyle(secondaryText.opacity(0.75))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if rememberEmail {
                    email = rememberedEmail
                }
            }
            .sheet(isPresented: $showRegister) {
                RegisterView()
                    .environment(auth)
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordView()
                    .environment(auth)
            }
        }
    }

    private func finishLoginIfNeeded() {
        if errorMessage == nil {
            rememberedEmail = rememberEmail
                ? email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                : ""
        }
    }
}

#Preview {
    @Previewable @State var auth = AuthViewModel()
    LoginView().environment(auth)
}
