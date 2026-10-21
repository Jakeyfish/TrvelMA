import Foundation

/// Minimal Supabase Auth REST client. The publishable key is designed to be shipped
/// in a client app; authorization is still enforced by Supabase RLS policies.
enum SupabaseAuthClient {
    static let baseURL = URL(string: "https://lbdfqzeiweqbsklklcqr.supabase.co")!
    static let publishableKey = "sb_publishable_d4tmuPirsf8-wUDO0Frd7w_PcXME6rs"

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
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response)
    }

    private static func post<T: Decodable>(path: String, queryItems: [URLQueryItem] = [], body: [String: Any]) async throws -> T {
        var request = URLRequest(url: endpoint(path: path, queryItems: queryItems))
        request.httpMethod = "POST"
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response, data: data)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AuthError.message("服务器返回的数据格式无法识别，请稍后重试。")
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
            throw AuthError.message(friendlyMessage(message ?? "连接云端账号失败。"))
        }
    }

    private static func friendlyMessage(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("invalid login credentials") { return "邮箱或密码不正确。" }
        if lower.contains("email not confirmed") { return "请先到邮箱完成验证，再登录云端账号。" }
        if lower.contains("user already registered") { return "该邮箱已注册，请直接登录。" }
        if lower.contains("password should be at least") { return "密码长度不足，请至少输入 6 位。" }
        if lower.contains("rate limit") { return "操作过于频繁，请稍后再试。" }
        return message
    }

    enum AuthError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            if case let .message(message) = self { return message }
            return nil
        }
    }
}
