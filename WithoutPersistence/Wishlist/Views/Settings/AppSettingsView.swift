import SwiftUI
import UserNotifications
import SwiftData

private enum SettingsPage: String, Identifiable {
    case account, agencies, expenses, sync, flight, about
    var id: Self { self }
}

/// A settings page, rather than a long toolbar menu. Preferences keep their existing account keys.
struct AppSettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppLanguageSettings.self) private var languageSettings
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @AppStorage(NavigationProvider.defaultsKey) private var navigation = NavigationProvider.appleMaps.rawValue
    @AppStorage(BaseCurrencyCatalog.countryCodeKey) private var currency = BaseCurrencyCatalog.defaultCountryCode
    @State private var page: SettingsPage?
    @State private var purchaseAfterChildDismiss = false
    @State private var requestsVersion = false
    let onPurchase: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button { page = .account } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.fill")
                                .font(.title2).foregroundStyle(Color.accentColor)
                                .frame(width: 46, height: 46)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 5) {
                                Text("我的账号").font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text(LocalizedStringKey(auth.isCloudAccount ? "云端账号" : "本地账号"))
                                    .font(.body).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 19))
                    }.buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 9) {
                        sectionTitle("常用偏好")
                        VStack(spacing: 0) {
                            HStack {
                                Label("界面语言", systemImage: "globe")
                                Spacer(minLength: 12)
                                Picker(selection: Binding(get: { languageSettings.selectedLanguage }, set: { languageSettings.select($0) })) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(verbatim: language.nativeName).tag(language)
                                }
                            } label: { Text("界面语言") }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .accessibilityIdentifier("settings-language")
                            Divider()
                            HStack {
                                Label("默认导航", systemImage: "arrow.triangle.turn.up.right.diamond")
                                Spacer(minLength: 12)
                                Picker(selection: $navigation) {
                                ForEach(NavigationProvider.allCases) { provider in
                                    Text(LocalizedStringKey(provider.title)).tag(provider.rawValue)
                                }
                            } label: { Text("默认导航") }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .accessibilityIdentifier("settings-navigation")
                            Divider()
                            HStack {
                                Label("本位币", systemImage: "dollarsign.circle")
                                Spacer(minLength: 12)
                                Picker(selection: $currency) {
                                ForEach(BaseCurrencyCatalog.options) { option in
                                    Text("\(option.currencyCode) · \(locale.localizedString(forRegionCode: option.countryCode) ?? option.countryName)")
                                        .tag(option.countryCode)
                                }
                            } label: { Text("本位币") }
                            .labelsHidden()
                            .frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .accessibilityIdentifier("settings-currency")
                        }
                        .pickerStyle(.menu).tint(.primary)
                        .font(.body)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                        Text("更改本位币不会自动换算已保存的金额。")
                            .font(.body).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        sectionTitle("业务与服务")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            tile("合作旅行社", subtitle: "旅行社信息", icon: "building.2.fill") { page = .agencies }
                            tile("费用项目", subtitle: "费用名称", icon: "list.bullet.rectangle") { page = .expenses }
                            tile("数据同步", subtitle: "默认同步方式", icon: "arrow.triangle.2.circlepath.icloud") { page = .sync }
                            tile("航班查询", subtitle: "航班查询设置", icon: "airplane") { page = .flight }
                            if BillingReleaseConfiguration.plansVisible {
                                tile("版本与购买", subtitle: "恢复购买", icon: "cart") { onPurchase() }
                            } else {
                                tile("版本信息", subtitle: "构建号", icon: "info.circle") {
                                    requestsVersion = true
                                }
                            }
                            tile("帮助与关于", subtitle: "隐私政策", icon: "questionmark.circle") { page = .about }
                        }
                    }
                    Text(verbatim: SettingsBuildInformation.shortText)
                        .font(.body).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }.labelStyle(.iconOnly)
                }
            }
            .sheet(item: $page, onDismiss: {
                if purchaseAfterChildDismiss {
                    purchaseAfterChildDismiss = false
                    onPurchase()
                }
            }) { destination in
                switch destination {
                case .account:
                    MyAccountSettingsView(onPurchase: {
                        purchaseAfterChildDismiss = true
                        page = nil
                    })
                case .agencies:
                    if auth.serverEntitlement?.edition == .cloud { CloudTravelAgencyDirectoryView() }
                    else { TravelAgencyListView() }
                case .expenses: ExpenseItemManagementView()
                case .sync: CloudSyncPreferenceView()
                case .flight: VariFlightSettingsView()
                case .about: SettingsAboutView()
                }
            }
            .modifier(SettingsVersionAlert(requested: $requestsVersion))
        }
        .font(.body)
        .environment(\.locale, languageSettings.locale)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(LocalizedStringKey(title)).font(.body.weight(.medium)).foregroundStyle(.secondary)
    }

    private func tile(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor)
                Text(LocalizedStringKey(title)).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(LocalizedStringKey(subtitle)).font(.body).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain)
    }
}

private struct SettingsVersionAlert: ViewModifier {
    @Binding var requested: Bool
    @State private var isPresented = false
    @State private var message = ""

    func body(content: Content) -> some View {
        content
            .alert("版本信息", isPresented: $isPresented) {
                Button("关闭", role: .cancel) {}
            } message: {
                Text(verbatim: message)
            }
            .task(id: requested) {
                guard requested else { return }
                var details = SettingsBuildInformation.text
                #if LEGACY_STORE_EVIDENCE
                let evidence = await LegacyLocalAccessReader.diagnosticSummary()
                details += "\n" + evidence
                #endif
                guard !Task.isCancelled else { return }
                message = details
                isPresented = true
                requested = false
            }
    }
}

enum SettingsBuildInformation {
    static var shortText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }
    static var text: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(AppLocalization.text("App 版本"))：\(version)\n\(AppLocalization.text("构建号"))：\(build)"
    }
}

struct MyAccountSettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let onPurchase: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("我的账号", value: auth.currentSalutation.isEmpty ? auth.currentEmail : auth.currentSalutation)
                    LabeledContent("邮箱", value: auth.currentEmail)
                    LabeledContent("账号类型", value: AppLocalization.text(auth.isCloudAccount ? "云端账号" : "本地账号"))
                } header: {
                    Text("个人资料").font(.body.weight(.medium))
                }
                Section {
                    NavigationLink { AccountSecuritySettingsView() } label: {
                        Label("账号与数据安全", systemImage: "lock.shield")
                    }
                    if auth.isCloudAccount {
                        if BillingReleaseConfiguration.salesEnabled {
                            NavigationLink { FlightBeanWalletView() } label: {
                                HStack { SilverBeanIcon(); Text("邀请赚云豆") }
                            }
                        }
                        NavigationLink { FlightMessageInboxView() } label: {
                            Label("航班管家", systemImage: "airplane")
                        }
                    }
                    if BillingReleaseConfiguration.plansVisible {
                        Button(action: onPurchase) { Label("版本与购买", systemImage: "cart") }
                    }
                }
            }
            .font(.body)
            .navigationTitle("我的账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() }.font(.body) } }
        }
    }
}

struct SilverBeanIcon: View {
    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [.white, Color(white: 0.50)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
            .frame(width: 20, height: 13)
            .rotationEffect(.degrees(-28))
            .accessibilityHidden(true)
    }
}

struct FlightBeanWalletView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var wallet: SupabaseAuthClient.FlightBeanWallet?
    @State private var invite = ""
    @State private var error = false
    @State private var saving = false

    var body: some View {
        List {
            if let wallet {
                Section {
                    LabeledContent { Text(wallet.balance, format: .number) } label: {
                        HStack { SilverBeanIcon(); Text("云豆余额") }
                    }
                    if let period = wallet.period_end,
                       let date = ISO8601DateFormatter().date(from: period) {
                        LabeledContent("当前订阅周期结束", value: date.formatted(.dateTime.year().month().day()))
                    }
                }
                Section("邀请赚云豆") {
                    Text(wallet.invite_code).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    ShareLink(item: wallet.invite_code) { Label("分享邀请码", systemImage: "square.and.arrow.up") }
                    if !wallet.referral_bound {
                        TextField("邀请码", text: $invite).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        Button("绑定邀请码") { Task { await bind() } }
                            .disabled(invite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                    }
                }
                Section("云豆明细") {
                    ForEach(wallet.entries) { entry in
                        LabeledContent(entryLabel(entry.kind), value: entry.amount.formatted(.number.sign(strategy: .always())))
                    }
                }
            }
            if error { Text("暂时无法完成操作，请重试。").foregroundStyle(.secondary) }
        }
        .navigationTitle("云豆")
        .task(id: auth.currentEmail) { wallet = nil; await load() }
        .refreshable { await load() }
    }

    private func entryLabel(_ kind: String) -> LocalizedStringKey {
        switch kind {
        case "subscription": return "订阅发放"
        case "refresh": return "航班刷新"
        case "referral": return "邀请奖励"
        case "subscription_refund", "referral_refund": return "退款扣回"
        default: return "云豆"
        }
    }

    private func load() async {
        guard let access = auth.cloudAccessToken else { return }
        let email = auth.currentEmail
        do {
            let result = try await SupabaseAuthClient.flightBeanWallet(accessToken: access)
            guard !Task.isCancelled, auth.currentEmail == email else { return }
            wallet = result
            error = false
        } catch {
            if !Task.isCancelled, auth.currentEmail == email { self.error = true }
        }
    }

    private func bind() async {
        guard let access = auth.cloudAccessToken else { return }
        let email = auth.currentEmail
        saving = true
        defer { saving = false }
        do {
            let bound = try await SupabaseAuthClient.bindFlightBeanInvite(invite, accessToken: access)
            guard auth.currentEmail == email else { return }
            guard bound else { error = true; return }
            invite = ""
            await load()
        } catch {
            if auth.currentEmail == email { self.error = true }
        }
    }
}

enum FlightPushPreference {
    private static func key(_ email: String) -> String { "flight.push.enabled." + email.lowercased() }
    static func isEnabled(email: String) -> Bool { UserDefaults.standard.bool(forKey: key(email)) }
    static func set(_ enabled: Bool, email: String) { UserDefaults.standard.set(enabled, forKey: key(email)) }
}

private struct FlightMessageInboxView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var messages: [SupabaseAuthClient.FlightMessage] = []
    @State private var failed = false

    @State private var pushEnabled = false
    @State private var pushFailed = false
    @State private var enrollingEmail: String?

    var body: some View {
        List {
            Section {
                Button { Task { await changePush() } } label: {
                    Text(LocalizedStringKey(pushEnabled ? "关闭航班推送" : "开启航班推送"))
                }
                .disabled(enrollingEmail != nil)
                Text("通知包含客人名称及航班信息。").font(.footnote).foregroundStyle(.secondary)
                if pushFailed { Text("航班推送暂不可用。").foregroundStyle(.secondary) }
            }
            if failed { Text("暂时无法完成操作，请重试。") }
            else if messages.isEmpty { Text("暂无航班消息") }
            ForEach(messages) { message in
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.title).font(.headline)
                    Text(message.body)
                    Text(message.created_at).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("航班管家")
        .task(id: auth.currentEmail) {
            messages = []
            enrollingEmail = nil
            pushEnabled = FlightPushPreference.isEnabled(email: auth.currentEmail)
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .flightPushRegistered)) { event in
            guard let email = enrollingEmail else { return }
            Task { await finishPush(event.object as? String, email: email) }
        }
        .refreshable { await load() }
    }

    private func changePush() async {
        pushFailed = false
        let email = auth.currentEmail
        if pushEnabled {
            guard let access = auth.cloudAccessToken else { return }
            do {
                guard try await SupabaseAuthClient.setFlightPushDevice(token: nil, accessToken: access) else {
                    pushFailed = true
                    return
                }
                FlightPushPreference.set(false, email: email)
                if auth.currentEmail == email { pushEnabled = false }
            } catch { pushFailed = true }
            return
        }
        do {
            guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) else {
                pushFailed = true
                return
            }
            guard auth.currentEmail == email else { return }
            enrollingEmail = email
            UIApplication.shared.registerForRemoteNotifications()
        } catch { pushFailed = true }
    }

    private func finishPush(_ token: String?, email: String) async {
        defer { if enrollingEmail == email { enrollingEmail = nil } }
        guard auth.currentEmail == email else { return }
        guard let token, let access = auth.cloudAccessToken else { pushFailed = true; return }
        do {
            let registered = try await SupabaseAuthClient.setFlightPushDevice(token: token, accessToken: access)
            guard auth.currentEmail == email else { return }
            FlightPushPreference.set(registered, email: email)
            pushEnabled = registered
            pushFailed = !registered
        } catch { pushFailed = true }
    }

    private func load() async {
        guard let access = auth.cloudAccessToken else { return }
        let email = auth.currentEmail
        do {
            let result = try await SupabaseAuthClient.flightMessages(accessToken: access)
            guard !Task.isCancelled, auth.currentEmail == email else { return }
            messages = result
            failed = false
        } catch {
            if !Task.isCancelled, auth.currentEmail == email { failed = true }
        }
    }
}

private struct SettingsAboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPrivacy = false
    @State private var requestsVersion = false
    var body: some View {
        NavigationStack {
            List {
                Button("版本信息") { requestsVersion = true }
                Button("隐私政策") { showPrivacy = true }
                Link("联系支持", destination: URL(string: "mailto:jason5101.wu@gmail.com")!)
            }
            .font(.body)
            .navigationTitle("帮助与关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .sheet(isPresented: $showPrivacy) { PrivacyPolicyView() }
            .modifier(SettingsVersionAlert(requested: $requestsVersion))
        }
    }
}

private struct AccountSecuritySettingsView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(DataSource.self) private var dataSource
    @Environment(\.modelContext) private var modelContext
    @State private var showingCloudDeletion = false
    @State private var accountDeletionAlert: AccountDeletionAlert?
    var body: some View {
        List {
            if auth.isCloudAccount {
                Button("清除此账号的本机资料", role: .destructive) { accountDeletionAlert = .cloudLocalDataConfirmation }
                    .disabled(auth.isCloudSyncInProgress)
            }
            Button("删除账户", role: .destructive) {
                if auth.isCloudAccount { showingCloudDeletion = true }
                else { accountDeletionAlert = .confirmation }
            }
            Button("退出登录", role: .destructive) { auth.logout() }
        }
        .font(.body)
        .navigationTitle("账号与数据安全")
        .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingCloudDeletion) { CloudAccountDeletionView() }
            .alert(item: $accountDeletionAlert) { alert in
                switch alert {
                case .confirmation:
                    Alert(
                        title: Text("确定删除账户？"),
                        message: Text("此操作将删除此设备上的全部账户及相关本地资料，并清空登录状态和本地缓存。删除后无法恢复。本地账号的删除不影响其他云端账号。"),
                        primaryButton: .destructive(Text("删除"), action: deleteAccount),
                        secondaryButton: .cancel(Text("取消"))
                    )
                case .cloudLocalDataConfirmation:
                    Alert(
                        title: Text("清除本机资料？"),
                        message: Text("只会删除当前登录账号保存在此设备上的行程管家资料和缓存。云端数据与其他账号不受影响。清除后无法从本机恢复；云端仍有资料时，可以再次同步下载。"),
                        primaryButton: .destructive(Text("清除本机资料"), action: clearCloudAccountLocalData),
                        secondaryButton: .cancel(Text("取消"))
                    )
                case .failure(let message):
                    Alert(
                        title: Text("删除失败"),
                        message: Text(message),
                        dismissButton: .default(Text("关闭"))
                    )
                case .cloudLocalDataFailure(let message):
                    Alert(
                        title: Text("清除失败"),
                        message: Text(message),
                        dismissButton: .default(Text("关闭"))
                    )
                case .cloudLocalDataSuccess:
                    Alert(
                        title: Text("本机资料已清除"),
                        message: Text("当前账号保存在此设备上的资料和缓存已清除。云端数据与其他账号没有更改。"),
                        dismissButton: .default(Text("关闭"))
                    )
                }
            }

    }

    private func deleteAccount() {
        do {
            try auth.deleteAllLocalData(context: modelContext)
            dataSource.clearAllUserData()
        } catch {
            accountDeletionAlert = .failure(error.localizedDescription)
        }
    }

    private func clearCloudAccountLocalData() {
        do {
            try auth.clearCurrentCloudAccountLocalData(context: modelContext)
            accountDeletionAlert = .cloudLocalDataSuccess
        } catch {
            accountDeletionAlert = .cloudLocalDataFailure(error.localizedDescription)
        }
    }
}

private enum AccountDeletionAlert: Identifiable {
    case confirmation
    case failure(String)
    case cloudLocalDataConfirmation
    case cloudLocalDataFailure(String)
    case cloudLocalDataSuccess

    var id: String {
        switch self {
        case .confirmation: "confirmation"
        case .failure: "failure"
        case .cloudLocalDataConfirmation: "cloud-local-data-confirmation"
        case .cloudLocalDataFailure: "cloud-local-data-failure"
        case .cloudLocalDataSuccess: "cloud-local-data-success"
        }
    }
}
