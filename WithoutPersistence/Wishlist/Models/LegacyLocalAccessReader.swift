import StoreKit

/// No persistent cache or explicit AppTransaction.refresh()/AppStore.sync() call.
/// Sandbox fixtures never confer production legacy access.
enum LegacyLocalAccessReader {
    static func decision(expectedBundleID: String, firstPaidBuild: String?) async -> LegacyLocalAccessDecision {
        guard firstPaidBuild != nil else { return .notConfigured }
        do {
            let result = try await AppTransaction.shared
            guard case .verified(let transaction) = result else { return .signatureUnverified }
            let environment: LegacyLocalAccessEvidence.Environment
            switch transaction.environment {
            case .production: environment = .production
            case .sandbox: environment = .sandbox
            case .xcode: environment = .xcode
            default: environment = .unknown
            }
            let evidence = LegacyLocalAccessEvidence(bundleID: transaction.bundleID,
                originalBuild: transaction.originalAppVersion,
                originalPurchaseDate: transaction.originalPurchaseDate, environment: environment)
            return LegacyLocalAccessPolicy.evaluate(evidence, expectedBundleID: expectedBundleID, firstPaidBuild: firstPaidBuild)
        } catch {
            // Unknown must never be interpreted as a new customer or permission to charge.
            return .evidenceUnavailable
        }
    }
}
