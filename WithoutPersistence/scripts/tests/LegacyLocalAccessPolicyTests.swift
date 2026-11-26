import Foundation

@main struct LegacyLocalAccessPolicyTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            precondition(condition(), name)
            checks += 1
        }
        check(LegacyLocalAccessPolicy.validPaidCutover("18", currentBuild: "18"), "First paid build can equal the cutoff")
        check(LegacyLocalAccessPolicy.validPaidCutover("18", currentBuild: "20"), "Later builds keep the original cutoff")
        check(!LegacyLocalAccessPolicy.validPaidCutover("18", currentBuild: "16"), "Cutoff cannot precede its release")
        check(!LegacyLocalAccessPolicy.validPaidCutover("", currentBuild: "18"), "Missing cutover cannot activate")
        check(!LegacyLocalAccessPolicy.validPaidCutover("0", currentBuild: "18"), "A zero cutoff cannot activate")
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
        // Observed production originals on the old and newly acquired Apple accounts.
        // Build 18 is a fixture boundary and does not configure the release.
        let simulatedCutover = "18"
        let routingCases: [(String, LegacyLocalAccessEvidence?, Bool, LegacyLocalAccessPolicy.WorkspaceAccess)] = [
            ("Original launch build remains editable", evidence("11"), false, .editable),
            ("Last verified free build remains editable", evidence("16"), false, .editable),
            ("Any build below the hypothetical boundary remains eligible", evidence("17"), false, .editable),
            ("First paid build offers purchase", evidence("18"), false, .readOnlyNeedsPurchase),
            ("First paid build restores editing after buyout", evidence("18"), true, .editable),
            ("Missing evidence offers verification", nil, false, .readOnlyNeedsVerification),
            ("Sandbox 16 cannot substitute for production", evidence("16", .sandbox), false, .readOnlyNeedsVerification),
        ]
        for (name, proof, purchased, expected) in routingCases {
            let result = decision(proof, simulatedCutover)
            check(LegacyLocalAccessPolicy.workspaceAccess(enforcementEnabled: true,
                decision: result, hasProductionPurchase: purchased) == expected, name)
            check(LegacyLocalAccessPolicy.allowsLocalPurchase(decision: result, hasPurchase: purchased,
                cutoverConfigured: true) == expected.allowsPurchase, name + " (purchase manager)")
        }
        check(LegacyLocalAccessPolicy.sandboxReviewAccess(enabled: false, verifiedSandboxApp: true,
            hasVerifiedSandboxPurchase: true) == nil, "Ordinary builds ignore sandbox review evidence")
        check(LegacyLocalAccessPolicy.sandboxReviewAccess(enabled: true, verifiedSandboxApp: false,
            hasVerifiedSandboxPurchase: true) == .readOnlyNeedsVerification, "A sandbox transaction cannot unlock a non-sandbox app")
        check(LegacyLocalAccessPolicy.sandboxReviewAccess(enabled: true, verifiedSandboxApp: true,
            hasVerifiedSandboxPurchase: false) == .readOnlyNeedsPurchase, "Review sandbox offers the local buyout")
        check(LegacyLocalAccessPolicy.sandboxReviewAccess(enabled: true, verifiedSandboxApp: true,
            hasVerifiedSandboxPurchase: true) == .editable, "Verified review sandbox buyout unlocks editing")
        print("PASS: \(checks) legacy local policy checks; synthetic evidence only")
    }
}
