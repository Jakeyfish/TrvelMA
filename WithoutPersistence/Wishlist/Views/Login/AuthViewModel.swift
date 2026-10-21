import Foundation
import Observation
import Security
import SwiftData
import UserNotifications

/// Supports on-device accounts and Supabase email/password authentication.
@Observable
final class AuthViewModel {
    private(set) var isLoggedIn = false
    private(set) var currentEmail = ""
    private(set) var currentSalutation = ""
    private(set) var currentPhone = ""
    private(set) var isCloudAccount = false
    private(set) var isCloudSyncInProgress = false

    func setCloudSyncInProgress(_ inProgress: Bool) {
        isCloudSyncInProgress = inProgress
    }
    var cloudAccessToken: String? {
        guard isCloudAccount else { return nil }
        return SecureCloudSession.load(key: "auth.cloud.accessToken")
    }

    func refreshCloudAccessToken() async -> String? {
        guard isCloudAccount,
              let refreshToken = SecureCloudSession.load(key: "auth.cloud.refreshToken") else { return nil }
        do {
            let response = try await SupabaseAuthClient.refreshSession(refreshToken: refreshToken)
            guard let access = response.accessToken, let refresh = response.refreshToken,
                  SecureCloudSession.save(access, key: "auth.cloud.accessToken"),
                  SecureCloudSession.save(refresh, key: "auth.cloud.refreshToken") else { return nil }
            if let phone = response.user?.userMetadata?.phone {
                currentPhone = phone
                UserDefaults.standard.set(phone, forKey: sessionPhoneKey)
            }
            return access
        } catch {
            return nil
        }
    }

    private let sessionEmailKey = "auth.session.email"
    private let sessionSalutationKey = "auth.session.salutation"
    private let sessionPhoneKey = "auth.session.phone"
    private let sessionExpirationKey = "auth.session.expiresAt"

    init() {
        restoreSession()
    }

    /// The demo flow uses a fixed code because no email/SMS delivery service is configured.
    let demoVerificationCode = "123456"

    func login(email: String, password: String, context: ModelContext) -> String? {
        let normalizedEmail = Self.normalize(email)
        guard Self.isValidEmail(normalizedEmail), !password.isEmpty else {
            return "请输入有效的邮箱和密码。"
        }
        let localAccount = account(for: normalizedEmail, in: context)
        let storedPassword = localAccount.flatMap { PasswordKeychain.password(for: $0.email) }
        let isLegacyDemoLogin = normalizedEmail == "test@test.com"
            && password == "123456"
            && storedPassword == nil
        guard storedPassword == password || isLegacyDemoLogin else {
            return "邮箱或密码不正确。"
        }
        let localScope = DataOwnership.localScope(email: normalizedEmail)
        DataOwnership.activateLocal(scope: localScope)
        do {
            try DataOwnership.adoptLegacyLocalRecords(context: context, scope: localScope)
        } catch {
            return "迁移本机资料失败：\(error.localizedDescription)"
        }
        currentEmail = normalizedEmail
        currentSalutation = localAccount?.salutation ?? ""
        currentPhone = localAccount?.phone ?? ""
        UserDefaults.standard.set(normalizedEmail, forKey: "auth.lastLocalEmail")
        isCloudAccount = false
        isLoggedIn = true
        saveSession(for: normalizedEmail, salutation: currentSalutation, phone: currentPhone)
        return nil
    }

    func loginToCloud(email: String, password: String) async -> String? {
        let normalizedEmail = Self.normalize(email)
        guard Self.isValidEmail(normalizedEmail), !password.isEmpty else {
            return "请输入有效的邮箱和密码。"
        }
        do {
            let response = try await SupabaseAuthClient.signIn(email: normalizedEmail, password: password)
            guard let accessToken = response.accessToken, let refreshToken = response.refreshToken else {
                return "登录未完成，请检查邮箱验证状态后重试。"
            }
            let accessSaved = SecureCloudSession.save(accessToken, key: "auth.cloud.accessToken")
            let refreshSaved = SecureCloudSession.save(refreshToken, key: "auth.cloud.refreshToken")
            guard accessSaved && refreshSaved else {
                SecureCloudSession.delete(key: "auth.cloud.accessToken")
                SecureCloudSession.delete(key: "auth.cloud.refreshToken")
                return "无法在此设备安全保存云端登录状态，请检查钥匙串设置后重试。"
            }
            currentEmail = response.user?.email ?? normalizedEmail
            currentSalutation = response.user?.userMetadata?.salutation ?? ""
            currentPhone = response.user?.userMetadata?.phone ?? ""
            DataOwnership.activateCloud(email: currentEmail)
            isCloudAccount = true
            isLoggedIn = true
            saveSession(for: currentEmail, salutation: currentSalutation, phone: currentPhone, isCloud: true)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func registerCloud(email: String, salutation: String, phone: String, password: String) async -> String? {
        let normalizedEmail = Self.normalize(email)
        guard Self.isValidEmail(normalizedEmail) else { return "请输入有效的邮箱地址。" }
        guard phone.filter(\.isNumber).count >= 6 else { return "请输入有效的手机号。" }
        guard password.count >= 6 else { return "密码至少需要 6 位。" }
        do {
            let response = try await SupabaseAuthClient.signUp(
                email: normalizedEmail,
                password: password,
                salutation: salutation.trimmingCharacters(in: .whitespacesAndNewlines),
                phone: phone
            )
            guard let accessToken = response.accessToken, let refreshToken = response.refreshToken else {
                return "注册成功。请先到邮箱完成验证，再返回登录。"
            }
            let accessSaved = SecureCloudSession.save(accessToken, key: "auth.cloud.accessToken")
            let refreshSaved = SecureCloudSession.save(refreshToken, key: "auth.cloud.refreshToken")
            guard accessSaved && refreshSaved else {
                SecureCloudSession.delete(key: "auth.cloud.accessToken")
                SecureCloudSession.delete(key: "auth.cloud.refreshToken")
                return "账号已创建，但无法在此设备安全保存登录状态。请重新登录。"
            }
            currentEmail = response.user?.email ?? normalizedEmail
            currentSalutation = response.user?.userMetadata?.salutation ?? ""
            currentPhone = response.user?.userMetadata?.phone ?? phone
            DataOwnership.activateCloud(email: currentEmail)
            isCloudAccount = true
            isLoggedIn = true
            saveSession(for: currentEmail, salutation: currentSalutation, phone: currentPhone, isCloud: true)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func sendCloudPasswordRecovery(email: String) async -> String? {
        let normalizedEmail = Self.normalize(email)
        guard Self.isValidEmail(normalizedEmail) else { return "请输入有效的邮箱地址。" }
        do {
            try await SupabaseAuthClient.requestPasswordRecovery(email: normalizedEmail)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func register(email: String, salutation: String, phone: String, password: String, context: ModelContext) -> String? {
        let normalizedEmail = Self.normalize(email)
        guard Self.isValidEmail(normalizedEmail) else { return "请输入有效的邮箱地址。" }
        guard phone.filter(\.isNumber).count >= 6 else { return "请输入有效的手机号。" }
        guard password.count >= 6 else { return "密码至少需要 6 位。" }
        guard account(for: normalizedEmail, in: context) == nil else { return "该邮箱已注册，请直接登录。" }
        guard PasswordKeychain.save(password, for: normalizedEmail) else {
            return "无法安全保存密码，请检查设备钥匙串状态。"
        }

        context.insert(LocalAccount(email: normalizedEmail, salutation: salutation.trimmingCharacters(in: .whitespacesAndNewlines), phone: phone))
        do {
            try context.save()
            return nil
        } catch {
            context.rollback()
            PasswordKeychain.delete(for: normalizedEmail)
            return "保存账号失败：\(error.localizedDescription)"
        }
    }

    func resetPassword(email: String, verificationCode: String, newPassword: String, context: ModelContext) -> String? {
        let normalizedEmail = Self.normalize(email)
        guard Self.isValidEmail(normalizedEmail) else { return "请输入有效的邮箱地址。" }
        guard let account = account(for: normalizedEmail, in: context) else { return "该邮箱尚未注册。" }
        guard verificationCode == demoVerificationCode else { return "验证码不正确。演示验证码为 123456。" }
        guard newPassword.count >= 6 else { return "新密码至少需要 6 位。" }
        guard PasswordKeychain.save(newPassword, for: normalizedEmail) else {
            return "无法安全更新密码，请检查设备钥匙串状态。"
        }
        account.updatedAt = .now
        do {
            try context.save()
            return nil
        } catch {
            context.rollback()
            return "更新账号失败：\(error.localizedDescription)"
        }
    }

    func logout() {
        if isCloudAccount, let accessToken = SecureCloudSession.load(key: "auth.cloud.accessToken") {
            Task { await Self.remoteLogout(accessToken: accessToken) }
        }
        isLoggedIn = false
        currentEmail = ""
        currentSalutation = ""
        currentPhone = ""
        isCloudAccount = false
        isCloudSyncInProgress = false
        DataOwnership.activateLocal(email: currentEmail)
        SecureCloudSession.delete(key: "auth.cloud.accessToken")
        SecureCloudSession.delete(key: "auth.cloud.refreshToken")
        clearSavedSession()
    }

    /// Clears only the active cloud account's on-device cache. Remote records,
    /// the signed-in session, and other account scopes remain untouched.
    func clearCurrentCloudAccountLocalData(context: ModelContext) throws {
        guard isLoggedIn, isCloudAccount else {
            throw SupabaseAuthClient.AuthError.message("此操作仅适用于已登录的云端账号。")
        }
        guard !isCloudSyncInProgress else {
            throw SupabaseAuthClient.AuthError.message("同步正在进行，请同步完成后再清除本机资料。")
        }

        let email = Self.normalize(currentEmail)
        guard !email.isEmpty else {
            throw SupabaseAuthClient.AuthError.message("无法确认当前账号，请重新登录后重试。")
        }
        let scope = DataOwnership.cloudScope(for: email)
        guard DataOwnership.activeScope == scope else {
            throw SupabaseAuthClient.AuthError.message("当前账号资料范围已变化，请重新打开后重试。")
        }

        let customers = try context.fetch(FetchDescriptor<Custumer>(predicate: #Predicate { $0.ownerScope == scope }))
        let addresses = try context.fetch(FetchDescriptor<Address>(predicate: #Predicate { $0.ownerScope == scope }))
        let contacts = try context.fetch(FetchDescriptor<Connect>(predicate: #Predicate { $0.ownerScope == scope }))
        let agencies = try context.fetch(FetchDescriptor<TravelAgency>(predicate: #Predicate { $0.ownerScope == scope }))
        let trips = try context.fetch(FetchDescriptor<TripBookingRecord>(predicate: #Predicate { $0.ownerScope == scope }))
        let deletions = try context.fetch(FetchDescriptor<CloudSyncDeletion>(predicate: #Predicate { $0.ownerScope == scope }))
        let conflicts = try context.fetch(FetchDescriptor<CloudSyncConflict>(predicate: #Predicate { $0.ownerScope == scope }))

        for item in addresses { context.delete(item) }
        for item in contacts { context.delete(item) }
        for item in customers { context.delete(item) }
        for item in agencies { context.delete(item) }
        for item in trips { context.delete(item) }
        for item in deletions { context.delete(item) }
        for item in conflicts { context.delete(item) }
        try context.save()

        let reminderIDs = trips.flatMap { trip in
            ["trip-reminder-\(trip.id.uuidString)-1", "trip-reminder-\(trip.id.uuidString)-2"]
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: reminderIDs)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: reminderIDs)

        AccountAssetStore.removeCloudAssets(email: email)
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: NavigationProvider.defaultsKey)
        defaults.removeObject(forKey: "baseCurrency.countryCode.\(scope)")
        CloudLocalDataPreference.cloudDataOnly.save(for: email)
        defaults.set(true, forKey: "auth.cloud.initialLocalImportConsent.v1.\(email)")
        defaults.removeObject(forKey: "cloud.sync.retry.v1.\(email).failureCount")
        defaults.removeObject(forKey: "cloud.sync.retry.v1.\(email).nextAttemptAt")

        NotificationCenter.default.post(name: .accountScopedLocalDataDidClear, object: scope)
    }

    /// Deletes device data only for local accounts. Cloud account deletion requires a
    /// trusted server function and is deliberately blocked here to avoid partial deletion.
    func deleteAllLocalData(context: ModelContext) throws {
        guard !isCloudAccount else {
            throw SupabaseAuthClient.AuthError.message("当前登录的是云端账号。云端账号删除需要额外的安全服务配置，请勿误以为本次会删除云端账号或数据。")
        }
        let scope = DataOwnership.activeScope
        let customers = try context.fetch(FetchDescriptor<Custumer>(predicate: #Predicate { $0.ownerScope == scope }))
        let agencies = try context.fetch(FetchDescriptor<TravelAgency>(predicate: #Predicate { $0.ownerScope == scope }))
        let trips = try context.fetch(FetchDescriptor<TripBookingRecord>(predicate: #Predicate { $0.ownerScope == scope }))
        let deletions = try context.fetch(FetchDescriptor<CloudSyncDeletion>(predicate: #Predicate { $0.ownerScope == scope }))
        for customer in customers { context.delete(customer) }
        for agency in agencies { context.delete(agency) }
        for trip in trips { context.delete(trip) }
        for deletion in deletions { context.delete(deletion) }

        let email = currentEmail
        if let localAccount = account(for: email, in: context) {
            context.delete(localAccount)
        }
        let loginRecords = try context.fetch(FetchDescriptor<LoginInfo>(predicate: #Predicate { $0.username == email }))
        for login in loginRecords { context.delete(login) }
        try context.save()

        PasswordKeychain.delete(for: email)
        logout()
        UserDefaults.standard.removeObject(forKey: "auth.rememberEmail")
        UserDefaults.standard.removeObject(forKey: "auth.rememberedEmail")
        AccountAssetStore.removeLocalAssets(email: email)
        clearLocalCaches()
    }

    /// Rechecks the persisted one-month session when the app becomes active.
    func refreshSessionIfNeeded(now: Date = .now) {
        guard isLoggedIn else { return }
        guard let expiration = UserDefaults.standard.object(forKey: sessionExpirationKey) as? Date,
              expiration > now else {
            logout()
            return
        }
    }

    func refreshCurrentSalutation(context: ModelContext) {
        guard !currentEmail.isEmpty,
              let account = account(for: currentEmail, in: context) else { return }
        currentSalutation = account.salutation
        currentPhone = account.phone
        UserDefaults.standard.set(account.salutation, forKey: sessionSalutationKey)
        UserDefaults.standard.set(account.phone, forKey: sessionPhoneKey)
    }

    private func restoreSession(now: Date = .now) {
        guard let email = UserDefaults.standard.string(forKey: sessionEmailKey),
              let expiration = UserDefaults.standard.object(forKey: sessionExpirationKey) as? Date,
              expiration > now else {
            clearSavedSession()
            return
        }
        currentEmail = email
        currentSalutation = UserDefaults.standard.string(forKey: sessionSalutationKey) ?? ""
        currentPhone = UserDefaults.standard.string(forKey: sessionPhoneKey) ?? ""
        isCloudAccount = UserDefaults.standard.bool(forKey: "auth.session.isCloud")
        if isCloudAccount {
            DataOwnership.activateCloud(email: currentEmail)
        } else {
            DataOwnership.activateLocal(email: currentEmail)
        }
        isLoggedIn = true
    }

    private func saveSession(for email: String, salutation: String, phone: String, isCloud: Bool = false, now: Date = .now) {
        let expiration = Calendar.current.date(byAdding: .month, value: 1, to: now)
            ?? now.addingTimeInterval(30 * 24 * 60 * 60)
        UserDefaults.standard.set(email, forKey: sessionEmailKey)
        UserDefaults.standard.set(salutation, forKey: sessionSalutationKey)
        UserDefaults.standard.set(phone, forKey: sessionPhoneKey)
        UserDefaults.standard.set(expiration, forKey: sessionExpirationKey)
        UserDefaults.standard.set(isCloud, forKey: "auth.session.isCloud")
        if isCloud {
            DataOwnership.activateCloud(email: email)
        } else {
            DataOwnership.activateLocal(email: email)
        }
    }

    private func clearSavedSession() {
        UserDefaults.standard.removeObject(forKey: sessionEmailKey)
        UserDefaults.standard.removeObject(forKey: sessionSalutationKey)
        UserDefaults.standard.removeObject(forKey: sessionPhoneKey)
        UserDefaults.standard.removeObject(forKey: sessionExpirationKey)
        UserDefaults.standard.removeObject(forKey: "auth.session.isCloud")
        SecureCloudSession.delete(key: "auth.cloud.accessToken")
        SecureCloudSession.delete(key: "auth.cloud.refreshToken")
    }

    private func clearLocalCaches() {
        URLCache.shared.removeAllCachedResponses()

        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        for directory in [cacheDirectory, fileManager.temporaryDirectory].compactMap({ $0 }) {
            guard let cachedItems = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for item in cachedItems {
                try? fileManager.removeItem(at: item)
            }
        }
    }

    private static func remoteLogout(accessToken: String) async {
        var request = URLRequest(url: SupabaseAuthClient.endpoint(path: "/auth/v1/logout"))
        request.httpMethod = "POST"
        request.setValue(SupabaseAuthClient.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    private func account(for email: String, in context: ModelContext) -> LocalAccount? {
        let descriptor = FetchDescriptor<LocalAccount>(predicate: #Predicate { $0.email == email })
        return try? context.fetch(descriptor).first
    }

    private static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isValidEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }

        let local = String(parts[0])
        let domain = String(parts[1])
        guard !local.isEmpty,
              !local.hasPrefix("."),
              !local.hasSuffix("."),
              !local.contains(".."),
              local.allSatisfy({ $0.isLetter || $0.isNumber || ".!#$%&'*+/=?^_`{|}~-".contains($0) }) else { return false }

        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty
                && label.first != "-"
                && label.last != "-"
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}

private enum SecureCloudSession {
    private static let service = "com.yunshengtech.travelmanager.cloud-session"

    @discardableResult
    static func save(_ value: String, key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let data = Data(value.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum PasswordKeychain {
    private static let service = "com.wishlist.local-account-password"

    static func password(for email: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ password: String, for email: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email
        ]
        let data = Data(password.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func delete(for email: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: email
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}
