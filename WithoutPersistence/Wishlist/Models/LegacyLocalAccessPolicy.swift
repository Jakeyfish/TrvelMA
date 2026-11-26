import Foundation

/// Only a verified AppTransaction may be converted to this in-memory evidence.
/// Never derive it from local data, account signup dates or preference flags.
struct LegacyLocalAccessEvidence: Equatable, Sendable {
    enum Environment: Equatable, Sendable { case production, sandbox, xcode, unknown }
    let bundleID: String
    let originalBuild: String
    let originalPurchaseDate: Date
    let environment: Environment
}

/// CFBundleVersion is numeric, not a marketing-version or lexicographic string.
struct AppBuildVersion: Comparable, Sendable {
    private let components: [Int]

    init?(_ value: String) {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        var normalized = numbers
        while normalized.count > 1, normalized.last == 0 { normalized.removeLast() }
        components = normalized
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for i in 0..<max(lhs.components.count, rhs.components.count) {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }
}

enum LegacyLocalAccessDecision: Equatable, Sendable {
    case notConfigured
    case legacy
    case firstAcquiredAfterCutover
    case evidenceUnavailable
    case signatureUnverified
    case wrongApplication
    case testEnvironment
    case invalidBuild

    var grantsLegacyLocalAccess: Bool { self == .legacy }
}

enum LegacyLocalAccessPolicy {
    /// Use only for the local workspace. It never grants cloud or flight access.
    enum WorkspaceAccess: Equatable, Sendable {
        case unchanged
        case editable
        case readOnlyNeedsPurchase
        case readOnlyNeedsVerification

        var allowsEditing: Bool { self == .unchanged || self == .editable }
        var allowsPurchase: Bool { self == .readOnlyNeedsPurchase }
    }

    static func workspaceAccess(enforcementEnabled: Bool, decision: LegacyLocalAccessDecision,
                                hasProductionPurchase: Bool) -> WorkspaceAccess {
        guard enforcementEnabled else { return .unchanged }
        if hasProductionPurchase || decision.grantsLegacyLocalAccess { return .editable }
        return decision == .firstAcquiredAfterCutover ? .readOnlyNeedsPurchase : .readOnlyNeedsVerification
    }

    static func sandboxReviewAccess(enabled: Bool, verifiedSandboxApp: Bool,
                                    hasVerifiedSandboxPurchase: Bool) -> WorkspaceAccess? {
        guard enabled else { return nil }
        guard verifiedSandboxApp else { return .readOnlyNeedsVerification }
        return hasVerifiedSandboxPurchase ? .editable : .readOnlyNeedsPurchase
    }

    static func validPaidCutover(_ cutoff: String, currentBuild: String) -> Bool {
        guard let cutoff = AppBuildVersion(cutoff), let current = AppBuildVersion(currentBuild),
              let firstValidBuild = AppBuildVersion("1") else { return false }
        return cutoff >= firstValidBuild && cutoff <= current
    }

    static func allowsLocalPurchase(decision: LegacyLocalAccessDecision, hasPurchase: Bool, cutoverConfigured: Bool) -> Bool {
        guard !hasPurchase else { return false }
        // Existing sandbox acceptance remains available while production sales are off.
        guard cutoverConfigured else { return true }
        return decision == .firstAcquiredAfterCutover
    }

    static func evaluate(_ evidence: LegacyLocalAccessEvidence?, expectedBundleID: String,
                         firstPaidBuild: String?) -> LegacyLocalAccessDecision {
        // A release's build number is not automatically the billing cutover.
        guard let firstPaidBuild else { return .notConfigured }
        guard let cutoff = AppBuildVersion(firstPaidBuild) else { return .invalidBuild }
        guard let evidence else { return .evidenceUnavailable }
        guard evidence.bundleID == expectedBundleID else { return .wrongApplication }
        guard evidence.environment == .production else { return .testEnvironment }
        guard let original = AppBuildVersion(evidence.originalBuild) else { return .invalidBuild }
        return original < cutoff ? .legacy : .firstAcquiredAfterCutover
    }
}
