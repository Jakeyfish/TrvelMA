import Foundation
import Observation
import Security
import SwiftData

/// Local authentication backed by SwiftData account metadata and Keychain passwords.
@Observable
final class AuthViewModel {
    private(set) var isLoggedIn = false
    private(set) var currentEmail = ""
    private(set) var currentSalutation = ""

    private let sessionEmailKey = "auth.session.email"
    private let sessionSalutationKey = "auth.session.salutation"
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
        currentEmail = normalizedEmail
        currentSalutation = localAccount?.salutation ?? ""
        isLoggedIn = true
        saveSession(for: normalizedEmail, salutation: currentSalutation)
        return nil
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
        isLoggedIn = false
        currentEmail = ""
        currentSalutation = ""
        clearSavedSession()
    }

    /// Deletes every locally stored account and app-owned user record.
    /// No cloud service is configured in this app, so there is no remote data to delete.
    func deleteAllLocalData(context: ModelContext) throws {
        try context.delete(model: Address.self)
        try context.delete(model: Connect.self)
        try context.delete(model: Custumer.self)
        try context.delete(model: ProfileInfo.self)
        try context.delete(model: LoginInfo.self)
        try context.delete(model: LocalAccount.self)
        try context.delete(model: TripBookingRecord.self)
        try context.save()

        PasswordKeychain.deleteAll()
        logout()
        UserDefaults.standard.removeObject(forKey: "auth.rememberEmail")
        UserDefaults.standard.removeObject(forKey: "auth.rememberedEmail")
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
        UserDefaults.standard.set(account.salutation, forKey: sessionSalutationKey)
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
        isLoggedIn = true
    }

    private func saveSession(for email: String, salutation: String, now: Date = .now) {
        let expiration = Calendar.current.date(byAdding: .month, value: 1, to: now)
            ?? now.addingTimeInterval(30 * 24 * 60 * 60)
        UserDefaults.standard.set(email, forKey: sessionEmailKey)
        UserDefaults.standard.set(salutation, forKey: sessionSalutationKey)
        UserDefaults.standard.set(expiration, forKey: sessionExpirationKey)
    }

    private func clearSavedSession() {
        UserDefaults.standard.removeObject(forKey: sessionEmailKey)
        UserDefaults.standard.removeObject(forKey: sessionSalutationKey)
        UserDefaults.standard.removeObject(forKey: sessionExpirationKey)
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
