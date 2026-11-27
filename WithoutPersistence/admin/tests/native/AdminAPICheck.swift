import Foundation

private struct AssertionFailed: Error { let detail: String }
private func expect(_ condition: @autoclosure () -> Bool, _ detail: String) throws {
    guard condition() else { throw AssertionFailed(detail: detail) }
}

private final class FixtureProtocol: URLProtocol {
    static let factor = "10000000-0000-0000-0000-000000000001"
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let url = request.url!
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let factorPath = "/auth/v1/factors/" + Self.factor
        let output: (Int, String)
        switch (url.path, authorization) {
        case ("/auth/v1/token", nil) where url.query == "grant_type=password":
            output = (200, #"{"access_token":"fixture-aal1"}"#)
        case ("/auth/v1/user", "Bearer fixture-aal1"):
            output = (200, #"{"factors":[{"id":"\#(Self.factor)","factor_type":"totp","status":"verified"}]}"#)
        case (factorPath + "/challenge", "Bearer fixture-aal1"):
            output = (200, #"{"id":"fixture-challenge"}"#)
        case (factorPath + "/verify", "Bearer fixture-aal1"):
            output = (200, #"{"access_token":"fixture-aal2"}"#)
        case ("/rest/v1/rpc/admin_context", "Bearer fixture-aal2"):
            output = (200, #"{"applications":[{"id":"test","name":"行程管家","environment":"production","permission":"write"}]}"#)
        case ("/rest/v1/rpc/admin_users", "Bearer fixture-aal2"):
            output = (200, #"{"total":1,"users":[{"id":"fixture-owner","email":"demo@example.com","purpose":"development","effective_status":"expired","active_devices":1,"max_devices":4}]}"#)
        case ("/rest/v1/rpc/admin_user_detail", "Bearer fixture-aal2"):
            output = (200, #"{"entitlement":{"edition":"cloud","status":"expired","updated_at":"2026-11-23T11:00:00Z","expires_at":"2026-11-23T11:00:00.123456Z","max_devices":4},"devices":[{"device_id":"fixture-device","device_type":"ios","last_seen_at":null,"revoked_at":null}],"transactions":[]}"#)
        case ("/rest/v1/rpc/admin_set_entitlement", "Bearer fixture-aal2"):
            output = (403, #"{"message":"ADMIN_RECENT_MFA_REQUIRED"}"#)
        default:
            output = (403, #"{"message":"ADMIN_MFA_REQUIRED"}"#)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: output.0, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(output.1.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main struct AdminAPICheck {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FixtureProtocol.self]
        let api = AdminAPI(session: URLSession(configuration: config))
        try await api.signIn(email: "demo@example.com", password: "fixture")
        do {
            let _: UserPage = try await api.rpc("admin_users")
            throw AssertionFailed(detail: "AAL1 should fail")
        } catch let failure as AdminError { try expect(failure.status == 403, "AAL1 rejection") }

        let applications = try await api.verify("012345")
        guard let app = applications.first else { throw AssertionFailed(detail: "MFA context") }
        try expect(app.writable, "write binding")
        let page: UserPage = try await api.rpc("admin_users")
        guard let user = page.users.first else { throw AssertionFailed(detail: "users") }
        let detail: AccountDetail = try await api.rpc("admin_user_detail")
        try expect(user.effectiveStatus == "expired" && user.activeDevices == 1, "list decoding")
        try expect(detail.devices.first?.deviceId == "fixture-device", "device decoding")

        var grant = GrantDraft(detail.entitlement)
        try expect(grant.expiry != nil && grant.devices == 4, "copy existing authorization")
        try expect(!grant.valid, "reason required")
        grant.reason = "  生命周期测试  "
        try expect(grant.valid, "valid grant")
        let id = UUID()
        let payload = grant.parameters(app: app, account: user, previous: detail.entitlement, request: id)
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        try expect(body?["p_request"] as? String == id.uuidString, "idempotency key")
        try expect(body?["p_expected"] as? String == "2026-11-23T11:00:00Z", "optimistic lock")
        try expect(body?["p_reason"] as? String == "生命周期测试", "trim reason")
        do {
            let _: JSONValue = try await api.rpc("admin_set_entitlement", payload)
            throw AssertionFailed(detail: "stale MFA should fail")
        } catch let failure as AdminError { try expect(failure.message == "ADMIN_RECENT_MFA_REQUIRED", "recent MFA error") }
        print("PASS: MFA, permission rejection, account/device decoding, grant validation and request guards")
    }
}
