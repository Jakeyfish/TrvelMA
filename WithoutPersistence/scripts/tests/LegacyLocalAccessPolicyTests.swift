import Foundation

@main struct LegacyLocalAccessPolicyTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            checks += 1
        }
        let bundle = "com.yunshengtech.travelmanager"
        func evidence(_ build: String = "11", _ environment: LegacyLocalAccessEvidence.Environment = .production, _ id: String? = nil) -> LegacyLocalAccessEvidence {
            .init(bundleID: id ?? bundle, originalBuild: build, originalPurchaseDate: Date(timeIntervalSince1970: 1_375_340_400), environment: environment)
        }
        func decision(_ e: LegacyLocalAccessEvidence?, _ cutoff: String? = "14") -> LegacyLocalAccessDecision {
            LegacyLocalAccessPolicy.evaluate(e, expectedBundleID: bundle, firstPaidBuild: cutoff)
        }
        check(decision(evidence(), nil) == .notConfigured, "Do not invent a paid cutover")
        check(decision(nil) == .evidenceUnavailable, "Missing receipt is unknown, not new")
        check(decision(evidence()) == .legacy, "Pre-cutover production original build retains access")
        check(decision(evidence("14")) == .firstAcquiredAfterCutover, "Cutover is exclusive")
        check(decision(evidence("15")) == .firstAcquiredAfterCutover, "Later build is not legacy")
        check(decision(evidence("1.0", .sandbox)) == .testEnvironment, "Sandbox constant 1.0 cannot grant legacy access")
        check(decision(evidence("1", .xcode)) == .testEnvironment, "Local StoreKit is not production proof")
        check(decision(evidence("1", .unknown)) == .testEnvironment, "Unknown environment is not proof")
        check(decision(evidence("1", .production, "other.application")) == .wrongApplication, "Bundle binding")
        check(decision(evidence("not-a-build")) == .invalidBuild, "Malformed receipt version is unknown")
        check(decision(evidence(), "1.1-beta") == .invalidBuild, "Invalid cutover is not new-user classification")
        check(AppBuildVersion("9")! < AppBuildVersion("14")!, "Numeric, not lexicographic comparison")
        check(AppBuildVersion("1.9")! < AppBuildVersion("1.10")!, "Numeric components")
        check(AppBuildVersion("14") == AppBuildVersion("14.0.0"), "Trailing zero normalization")
        for invalid in ["", " 14", "14 ", "1..2", ".1", "1.", "1.2.3.4", "-1", "١٤", "999999999999999999999999999999"] {
            check(AppBuildVersion(invalid) == nil, "Reject malformed CFBundleVersion")
        }
        check(!LegacyLocalAccessDecision.evidenceUnavailable.grantsLegacyLocalAccess, "Unknown does not grant")
        check(!LegacyLocalAccessDecision.testEnvironment.grantsLegacyLocalAccess, "Sandbox does not grant")
        check(LegacyLocalAccessDecision.legacy.grantsLegacyLocalAccess, "Only verified old production evidence grants")
        for unknown in [LegacyLocalAccessDecision.evidenceUnavailable, .signatureUnverified, .testEnvironment, .invalidBuild, .notConfigured, .legacy] {
            check(!LegacyLocalAccessPolicy.allowsLocalPurchase(decision: unknown, hasPurchase: false, cutoverConfigured: true), "Unknown or grandfathered access cannot trigger purchase")
        }
        check(LegacyLocalAccessPolicy.allowsLocalPurchase(decision: .firstAcquiredAfterCutover, hasPurchase: false, cutoverConfigured: true), "Confirmed new customer can purchase")
        check(!LegacyLocalAccessPolicy.allowsLocalPurchase(decision: .firstAcquiredAfterCutover, hasPurchase: true, cutoverConfigured: true), "Existing purchase cannot buy again")
        check(LegacyLocalAccessPolicy.allowsLocalPurchase(decision: .notConfigured, hasPurchase: false, cutoverConfigured: false), "Keep sandbox acceptance working before production cutover configured")
        let allDecisions: [LegacyLocalAccessDecision] = [.notConfigured, .legacy, .firstAcquiredAfterCutover,
            .evidenceUnavailable, .signatureUnverified, .wrongApplication, .testEnvironment, .invalidBuild]
        for value in allDecisions {
            for purchased in [false, true] {
                let disabled = LegacyLocalAccessPolicy.workspaceAccess(enforcementEnabled: false, decision: value, hasProductionPurchase: purchased)
                check(disabled == .unchanged && disabled.allowsEditing && !disabled.allowsPurchase, "Disabled gate preserves current use without opening sales")
                let enabled = LegacyLocalAccessPolicy.workspaceAccess(enforcementEnabled: true, decision: value, hasProductionPurchase: purchased)
                check(enabled.allowsEditing == (purchased || value == .legacy), "Only production purchase or legacy proof grants editing")
                check(enabled.allowsPurchase == (!purchased && value == .firstAcquiredAfterCutover), "Unknown evidence must offer verification, not payment")
                if !purchased && value != .legacy && value != .firstAcquiredAfterCutover {
                    check(enabled == .readOnlyNeedsVerification, "Every unresolved state remains distinguishable from a new customer")
                }
            }
        }
        print("PASS: \(checks) legacy local policy checks; synthetic evidence only")
    }
}
