import StoreKit

/// No persistent cache or explicit AppTransaction.refresh()/AppStore.sync() call.
/// Sandbox fixtures never confer production legacy access.
enum LegacyLocalAccessReader {
    /// Shows only verification, environment, and build information. No signed payload is retained.
    static func diagnosticSummary() async -> String {
        do {
            guard case .verified(let transaction) = try await AppTransaction.shared else {
                return "App Store: signature unverified"
            }
            guard transaction.bundleID == Bundle.main.bundleIdentifier else {
                return "App Store: bundle mismatch"
            }
            return "App Store: \(transaction.environment.rawValue) · CFBundleVersion: \(transaction.originalAppVersion)"
        } catch {
            return "App Store: evidence unavailable"
        }
    }

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
