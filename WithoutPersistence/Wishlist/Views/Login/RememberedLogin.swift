import Foundation
import LocalAuthentication
import Security

struct RememberedLogin: Codable, Hashable, Identifiable {
    let email: String
    let isCloud: Bool
    var usesBiometrics = false

    var id: String { (isCloud ? "cloud:" : "local:") + email }

    init(email: String, isCloud: Bool, usesBiometrics: Bool = false) {
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        self.isCloud = isCloud
        self.usesBiometrics = usesBiometrics
    }
}

enum RememberedLogins {
    private static let storageKey = "auth.rememberedAccounts.v1"

    static func load(defaults: UserDefaults = .standard) -> [RememberedLogin] {
        if let data = defaults.data(forKey: storageKey),
           let accounts = try? JSONDecoder().decode([RememberedLogin].self, from: data) { return accounts }
        guard defaults.bool(forKey: "auth.rememberEmail"),
              let email = defaults.string(forKey: "auth.rememberedEmail"), !email.isEmpty else { return [] }
        let mode = defaults.object(forKey: "auth.accountMode.cloud") as? Bool ?? true
        let accounts = [RememberedLogin(email: email, isCloud: mode)]
        save(accounts, defaults: defaults)
        return accounts
    }

    static func save(_ accounts: [RememberedLogin], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        defaults.set(data, forKey: storageKey)
        defaults.removeObject(forKey: "auth.rememberedEmail")
    }

    static func record(_ account: RememberedLogin, defaults: UserDefaults = .standard) {
        save([account] + load(defaults: defaults).filter { $0.id != account.id }, defaults: defaults)
    }

    static func forget(_ account: RememberedLogin) {
        save(load().filter { $0.id != account.id })
        BiometricLogin.delete(account)
    }

    static func disableBiometrics(_ account: RememberedLogin) {
        save(load().map { entry in
            guard entry.id == account.id else { return entry }
            return RememberedLogin(email: entry.email, isCloud: entry.isCloud)
        })
        BiometricLogin.delete(account)
    }
}

enum BiometricLogin {
    private static let service = "com.yunshengtech.travelmanager.biometric-login"

    static var availableType: LABiometryType? {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            ? context.biometryType : nil
    }

    static func store(_ password: String, for account: RememberedLogin) -> Bool {
        guard availableType != nil, !password.isEmpty,
              let control = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
                    .biometryCurrentSet, nil) else { return false }
        // Replace only the selected identity's entry. The system invalidates
        // the new entry if the registered Face ID / Touch ID set is changed.
        delete(account)
        var item = query(account)
        item[kSecAttrAccessControl as String] = control
        item[kSecValueData as String] = Data(password.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func password(for account: RememberedLogin) async throws -> String {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        let reason = AppLocalization.text("验证身份以登录行程管家")
        guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) else {
            throw LAError(.authenticationFailed)
        }
        var item = query(account)
        item[kSecUseAuthenticationContext as String] = context
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else { throw LAError(.authenticationFailed) }
        return password
    }

    static func delete(_ account: RememberedLogin) {
        SecItemDelete(query(account) as CFDictionary)
    }

    private static func query(_ account: RememberedLogin) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account.id,
         kSecAttrSynchronizable as String: false]
    }
}
