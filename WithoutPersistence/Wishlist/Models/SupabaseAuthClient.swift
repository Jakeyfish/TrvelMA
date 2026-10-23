import Foundation
import UIKit

/// Minimal Supabase Auth REST client. The publishable key is designed to be shipped
/// in a client app; authorization is still enforced by Supabase RLS policies.
enum SupabaseAuthClient {
    static let baseURL = URL(string: "https://lbdfqzeiweqbsklklcqr.supabase.co")!
    static let publishableKey = "sb_publishable_d4tmuPirsf8-wUDO0Frd7w_PcXME6rs"
    private static let requestTimeout: TimeInterval = 20
    private static let accountDeviceIDKey = "auth.cloud.accountDeviceID.v1"

    /// Stable for this app vendor on this device. This is used only to enforce
    /// the account's registered-device allowance; it is never exposed in UI.
    static var accountDeviceID: String {
        if let identifier = UIDevice.current.identifierForVendor?.uuidString {
            return identifier.lowercased()
        }
        if let saved = UserDefaults.standard.string(forKey: accountDeviceIDKey) {
            return saved
        }
        let generated = UUID().uuidString.lowercased()
        UserDefaults.standard.set(generated, forKey: accountDeviceIDKey)
        return generated
    }

    static var accountDeviceType: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    static func applyAccountDeviceHeader(to request: inout URLRequest) {
        request.setValue(accountDeviceID, forHTTPHeaderField: "x-account-device-id")
    }

    struct AuthResponse: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let expiresIn: Int?
        let user: User?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case user
        }
    }

    struct User: Decodable {
        let email: String?
        let userMetadata: UserMetadata?

        enum CodingKeys: String, CodingKey {
            case email
            case userMetadata = "user_metadata"
        }
    }

    struct UserMetadata: Decodable {
        let salutation: String?
        let phone: String?
    }

    struct AccountEntitlement: Decodable, Encodable {
        enum Status: String, Codable {
            case active
            case grace
            case expired
            case revoked
        }

        let edition: ProductEdition
        let status: Status
        let expiresAt: String?
        let maxDevices: Int

        enum CodingKeys: String, CodingKey {
            case edition
            case status
            case expiresAt = "expires_at"
            case maxDevices = "max_devices"
        }

        var isCurrentlyActive: Bool {
            guard status == .active || status == .grace else { return false }
            guard let expiresAt, !expiresAt.isEmpty else { return true }
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let expiration = fractionalFormatter.date(from: expiresAt)
                ?? ISO8601DateFormatter().date(from: expiresAt)
            return expiration.map { $0 > .now } ?? false
        }
    }

    private struct DeviceRegistrationResult: Decodable {
        let activeDevices: Int
        let maxDevices: Int

        enum CodingKeys: String, CodingKey {
            case activeDevices = "active_devices"
            case maxDevices = "max_devices"
        }
    }

    enum AccountEntitlementLookup {
        case legacyTableUnavailable
        case noGrant
        case granted(AccountEntitlement)
    }

    static func signIn(email: String, password: String) async throws -> AuthResponse {
        try await post(path: "/auth/v1/token", queryItems: [URLQueryItem(name: "grant_type", value: "password")], body: [
            "email": email,
            "password": password
        ])
    }

    static func refreshSession(refreshToken: String) async throws -> AuthResponse {
        try await post(path: "/auth/v1/token", queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")], body: [
            "refresh_token": refreshToken
        ])
    }

    static func signUp(email: String, password: String, salutation: String, phone: String) async throws -> AuthResponse {
        try await post(path: "/auth/v1/signup", body: [
            "email": email,
            "password": password,
            "data": ["salutation": salutation, "phone": phone]
        ])
    }

    static func requestPasswordRecovery(email: String) async throws {
        let url = endpoint(path: "/auth/v1/recover")
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    static func fetchAccountEntitlement(accessToken: String) async throws -> AccountEntitlementLookup {
        let queryItems = [
            URLQueryItem(name: "select", value: "edition,status,expires_at,max_devices"),
            URLQueryItem(name: "limit", value: "1")
        ]
        var request = URLRequest(url: endpoint(path: "/rest/v1/account_entitlements", queryItems: queryItems))
        request.timeoutInterval = requestTimeout
        request.httpMethod = "GET"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 { return .legacyTableUnavailable }
        try validate(response, data: data)
        do {
            guard let entitlement = try JSONDecoder().decode([AccountEntitlement].self, from: data).first else {
                return .noGrant
            }
            return .granted(entitlement)
        } catch {
            throw AuthError.message(String(localized: "服务器返回的版本权益格式无法识别。", locale: AppLanguageSettings.currentLocale))
        }
    }

    static func registerCurrentDevice(accessToken: String) async throws {
        let _: DeviceRegistrationResult = try await post(
            path: "/rest/v1/rpc/register_account_device",
            body: [
                "p_device_id": accountDeviceID,
                "p_device_type": accountDeviceType
            ],
            accessToken: accessToken,
            includeDeviceHeader: false
        )
    }

    static func releaseCurrentDevice(accessToken: String) async {
        var request = URLRequest(url: endpoint(path: "/rest/v1/rpc/release_account_device"))
        request.timeoutInterval = requestTimeout
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["p_device_id": accountDeviceID])
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            try validate(response)
        } catch {
            // A failed logout-side release must not prevent local sign-out.
        }
    }

    private static func post<T: Decodable>(path: String, queryItems: [URLQueryItem] = [], body: [String: Any], accessToken: String? = nil, includeDeviceHeader: Bool = false) async throws -> T {
        var request = URLRequest(url: endpoint(path: path, queryItems: queryItems))
        request.timeoutInterval = requestTimeout
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        if includeDeviceHeader { applyAccountDeviceHeader(to: &request) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AuthError.message(String(localized: "服务器返回的数据格式无法识别，请稍后重试。", locale: AppLanguageSettings.currentLocale))
        }
    }

    static func endpoint(path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    private static func validate(_ response: URLResponse, data: Data = Data()) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = payload?["msg"] as? String
                ?? payload?["message"] as? String
                ?? payload?["error_description"] as? String
                ?? payload?["error"] as? String
            if message?.lowercased().contains("account_device_limit_reached") == true {
                throw AuthError.deviceLimitReached
            }
            throw AuthError.response(
                statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: friendlyMessage(message ?? String(localized: "连接云端账号失败。", locale: AppLanguageSettings.currentLocale))
            )
        }
    }

    private static func friendlyMessage(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("account_device_limit_reached") {
            return String(localized: "此账号已达到可用设备数。请在另一台设备退出登录后重试，或联系管理员增加设备额度。", locale: AppLanguageSettings.currentLocale)
        }
        if lower.contains("invalid login credentials") { return String(localized: "邮箱或密码不正确。", locale: AppLanguageSettings.currentLocale) }
        if lower.contains("email not confirmed") { return String(localized: "请先到邮箱完成验证，再登录云端账号。", locale: AppLanguageSettings.currentLocale) }
        if lower.contains("user already registered") { return String(localized: "该邮箱已注册，请直接登录。", locale: AppLanguageSettings.currentLocale) }
        if lower.contains("password should be at least") { return String(localized: "密码长度不足，请至少输入 6 位。", locale: AppLanguageSettings.currentLocale) }
        if lower.contains("rate limit") { return String(localized: "操作过于频繁，请稍后再试。", locale: AppLanguageSettings.currentLocale) }
        return String(localized: "云端账号操作失败，请稍后重试。", locale: AppLanguageSettings.currentLocale)
    }

    enum AuthError: LocalizedError {
        case message(String)
        case response(statusCode: Int, message: String)
        case deviceLimitReached
        var errorDescription: String? {
            switch self {
            case let .message(message), let .response(_, message): return message
            case .deviceLimitReached:
                return String(localized: "此账号已达到可用设备数。请在另一台设备退出登录后重试，或联系管理员增加设备额度。", locale: AppLanguageSettings.currentLocale)
            }
        }
    }
}
