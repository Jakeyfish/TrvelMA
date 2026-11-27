import Foundation

struct Application: Codable, Identifiable, Hashable {
    let id, name, environment, permission: String
    var writable: Bool { permission == "write" }
    var environmentLabel: String { ["production": "生产", "staging": "预发布", "sandbox": "沙盒"][environment] ?? environment }
}
struct Account: Codable, Identifiable, Hashable {
    let id, email, purpose, effectiveStatus: String
    let activeDevices: Int
    let maxDevices: Int?
}
struct Entitlement: Codable {
    let edition, status, updatedAt: String
    let expiresAt: String?
    let maxDevices: Int
}
struct Device: Codable, Identifiable {
    let deviceId, deviceType: String
    let lastSeenAt, revokedAt: String?
    var id: String { deviceId }
}
struct Transaction: Decodable {
    let environment, productId, purchasedAt: String
    let expiresAt, revokedAt: String?
}
struct AccountDetail: Decodable {
    let entitlement: Entitlement?
    let devices: [Device]
    let transactions: [Transaction]
}
struct UserPage: Decodable {
    let total: Int
    let users: [Account]
}
struct FlightBeanPolicy: Decodable {
    let cost: Int
    let updatedAt: String
}
struct AuditEntry: Decodable, Identifiable {
    let id: Int
    let occurredAt, actor, action: String
    let target, reason: String?
    let beforeValue, afterValue: JSONValue?
}
enum JSONValue: Codable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try box.decode([JSONValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .string(let value): try box.encode(value)
        case .number(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .object(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .null: try box.encodeNil()
        }
    }
    static func optional(_ value: String?) -> Self { value.map(Self.string) ?? .null }
    var formatted: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "—"
    }
}
struct AdminError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? {
        switch message {
        case "ADMIN_RECENT_MFA_REQUIRED": "请重新完成二次验证。"
        case "DEVICE_CHANGED_REFRESH", "ENTITLEMENT_CHANGED_REFRESH": "资料已变化，请返回详情重新加载后再操作。"
        case "FLIGHT_BEAN_POLICY_CHANGED_REFRESH": "扣豆规则已更新，请下拉刷新后重新修改。"
        case "MFA_SETUP_REQUIRED": "请先在现有 Web 后台设置验证器。"
        default: status == 403 ? "当前账号没有这项管理权限。" : status == 401 ? "登录或验证失败，请检查输入。" : "请求失败，请稍后重试（\(status)）。"
        }
    }
}
struct GrantDraft {
    var edition: String
    var status: String
    var devices: Int
    var expiry: Date?
    var reason: String = ""

    init(_ current: Entitlement?) {
        edition = current?.edition ?? "cloud"
        status = current?.status ?? "active"
        devices = current?.maxDevices ?? 4
        expiry = AdminDate.parse(current?.expiresAt)
    }

    var valid: Bool {
        ["local", "cloud", "sync"].contains(edition)
        && ["active", "grace", "expired", "revoked"].contains(status)
        && (1...100).contains(devices)
        && (4...500).contains(reason.trimmingCharacters(in: .whitespacesAndNewlines).count)
    }
    func parameters(app: Application, account: Account, previous: Entitlement?, request: UUID) -> [String: JSONValue] {
        ["p_app": .string(app.id), "p_owner": .string(account.id), "p_expected": .optional(previous?.updatedAt),
         "p_edition": .string(edition), "p_status": .string(status), "p_devices": .number(Double(devices)),
         "p_expiry": .optional(expiry.map(AdminDate.wire)), "p_reason": .string(reason.trimmingCharacters(in: .whitespacesAndNewlines)),
         "p_request": .string(request.uuidString)]
    }
}
enum AdminDate {
    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: text) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: text)
    }
    static func wire(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    static func display(_ text: String?, fallback: String = "—") -> String {
        parse(text)?.formatted(date: .abbreviated, time: .shortened) ?? fallback
    }
}

@MainActor
final class AdminAPI {
    private let host = URL(string: "https://lbdfqzeiweqbsklklcqr.supabase.co")!
    private let publishableKey = "sb_publishable_d4tmuPirsf8-wUDO0Frd7w_PcXME6rs"
    private let session: URLSession
    private var token: String?
    private(set) var factor: String?

    init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    func signIn(email: String, password: String) async throws {
        reset()
        let auth: Token = try await request("/auth/v1/token?grant_type=password", body: ["email": .string(email), "password": .string(password)])
        token = auth.accessToken
        let user: AuthUser = try await request("/auth/v1/user", method: "GET")
        let factors = (user.factors ?? []).filter { $0.factorType == "totp" }
        factor = factors.first { $0.status == "verified" }?.id
            ?? factors.first { $0.status == "unverified" && $0.friendlyName == "云盛管理后台" }?.id
        guard factor != nil else { reset(); throw AdminError(status: 403, message: "MFA_SETUP_REQUIRED") }
    }

    func verify(_ code: String) async throws -> [Application] {
        guard let factor, let id = UUID(uuidString: factor) else { throw AdminError(status: 401, message: "") }
        let path = "/auth/v1/factors/\(id.uuidString.lowercased())"
        let challenge: Challenge = try await request(path + "/challenge", body: [:])
        let result: Token = try await request(path + "/verify", body: ["challenge_id": .string(challenge.id), "code": .string(code)])
        token = result.accessToken
        let context: Context = try await rpc("admin_context")
        return context.applications
    }

    func rpc<T: Decodable>(_ name: String, _ body: [String: JSONValue] = [:]) async throws -> T {
        try await request("/rest/v1/rpc/" + name, body: body)
    }

    func logout() async {
        defer { reset() }
        guard token != nil else { return }
        let _: JSONValue? = try? await request("/auth/v1/logout?scope=local", body: [:])
    }

    func reset() { token = nil; factor = nil }

    private func request<T: Decodable>(_ path: String, method: String = "POST", body: [String: JSONValue]? = nil) async throws -> T {
        var request = URLRequest(url: URL(string: path, relativeTo: host)!.absoluteURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw AdminError(status: response.statusCode, message: error?.message ?? "")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data.isEmpty ? Data("null".utf8) : data)
    }

    private struct Token: Decodable { let accessToken: String }
    private struct Challenge: Decodable { let id: String }
    private struct Context: Decodable { let applications: [Application] }
    private struct AuthUser: Decodable { let factors: [Factor]? }
    private struct Factor: Decodable { let id, factorType, status: String; let friendlyName: String? }
    private struct ErrorBody: Decodable { let message: String? }
}
