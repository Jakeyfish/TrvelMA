import Foundation
import StoreKit
import Observation
import UIKit

enum BillingReleaseConfiguration {
    #if DEBUG && STOREKIT_SANDBOX_ACCEPTANCE
    static let sandboxAcceptanceBuild = true
    #else
    static let sandboxAcceptanceBuild = false
    #endif
    #if STOREKIT_CLOUD_REVIEW
    static let cloudReviewBuild = true
    #else
    static let cloudReviewBuild = false
    #endif

    #if (DEBUG && STOREKIT_SANDBOX_ACCEPTANCE) || STOREKIT_CLOUD_REVIEW
    static let sandboxOwnerID = UUID(uuidString: "71b164e4-7dbf-4433-8503-84ed156171de")!
    static let sandboxOwnerIDs: Set<UUID> = [sandboxOwnerID, UUID(uuidString: "86361373-d4ba-4fc6-8f38-420367b6484e")!]
    #else
    static let sandboxOwnerID: UUID? = nil
    static let sandboxOwnerIDs: Set<UUID> = []
    #endif
    // Production activation requires an explicit Release build and an approved version boundary.
    static let firstPaidLocalBuild: String? = {
        #if STOREKIT_PAID_RELEASE && !DEBUG && !STOREKIT_LOCAL_REVIEW && !STOREKIT_CLOUD_REVIEW
        guard let cutoff = Bundle.main.object(forInfoDictionaryKey: "TrvelMAFirstPaidBuild") as? String,
              let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              LegacyLocalAccessPolicy.validPaidCutover(cutoff, currentBuild: current) else { return nil }
        return cutoff
        #else
        return nil
        #endif
    }()
    static let paidReleaseBuild = firstPaidLocalBuild != nil
    static let localAccessEnforcementEnabled = paidReleaseBuild
    #if STOREKIT_LOCAL_REVIEW
    static let localReviewBuild = true
    #else
    static let localReviewBuild = false
    #endif
    static let reviewBuild = localReviewBuild || cloudReviewBuild
    static let sandboxOnlyBuild = sandboxAcceptanceBuild || reviewBuild
    static let salesEnabled = sandboxOnlyBuild || paidReleaseBuild
    static let plansVisible = salesEnabled

    static func permitsReviewProduct(_ productID: String, verifiedSandbox: Bool,
                                     localReview: Bool = localReviewBuild,
                                     cloudReview: Bool = cloudReviewBuild) -> Bool {
        guard localReview || cloudReview else { return true }
        guard verifiedSandbox else { return false }
        return productID == StoreProductCatalog.local ? localReview
            : cloudReview && StoreProductCatalog.isCloud(productID)
    }

    static func permits(environment: AppStore.Environment, sandboxOnly: Bool) -> Bool {
        !sandboxOnly || environment == .sandbox
    }
}

/// Product IDs are stable. Prices must come from StoreKit's localized Product data.
enum StoreProductCatalog {
    static let local = "com.yunshengtech.travelmanager.local.lifetime"
    static let monthly = "com.yunshengtech.travelmanager.cloud.monthly"
    static let yearly = "com.yunshengtech.travelmanager.cloud.yearly"
    static let all = [local, monthly, yearly]
    static func isCloud(_ id: String) -> Bool { id == monthly || id == yearly }
    static func isActive(productID: String, revokedAt: Date?, expiresAt: Date?, upgraded: Bool, now: Date = .now) -> Bool {
        all.contains(productID) && revokedAt == nil && !upgraded && (expiresAt.map { $0 > now } ?? (productID == local))
    }
}

/// Pure selection policy. Only the named lifecycle QA owner can request a Sandbox refund.
/// Expired periods remain eligible for Apple's own decision; no app-side entitlement is changed.
enum SandboxRefundPolicy {
    static let lifecycleOwner = UUID(uuidString: "86361373-d4ba-4fc6-8f38-420367b6484e")!
    static func permits(buildEnabled: Bool, owner: UUID?, transactionOwner: UUID?, product: String,
                        environment: AppStore.Environment, revoked: Bool, upgraded: Bool) -> Bool {
        buildEnabled && owner == lifecycleOwner && transactionOwner == owner
            && StoreProductCatalog.isCloud(product) && environment == .sandbox && !revoked && !upgraded
    }
}

/// Cloud grants are deliberately injected only after server signature verification is deployed.
/// No UI setting or UserDefaults flag can enable production sales.
@MainActor @Observable final class StorePurchaseManager {
    typealias CloudVerifier = @MainActor (_ signedTransaction: String, _ accountID: UUID) async throws -> Void
    typealias CloudPurchasePreflight = @MainActor (_ accountID: UUID) async throws -> Void
    static let shared = StorePurchaseManager()
    private(set) var products: [Product] = []
    private(set) var hasLocalPurchase = false
    // Separate from sandbox UI state: test transactions never unlock production use.
    private(set) var hasProductionLocalPurchase = false
    private var sandboxReviewVerified = false
    private var hasSandboxReviewPurchase = false
    private(set) var legacyLocalDecision: LegacyLocalAccessDecision = .notConfigured
    var localWorkspaceAccess: LegacyLocalAccessPolicy.WorkspaceAccess {
        if let reviewAccess = LegacyLocalAccessPolicy.sandboxReviewAccess(
            enabled: BillingReleaseConfiguration.localReviewBuild || (BillingReleaseConfiguration.paidReleaseBuild && sandboxReviewVerified), verifiedSandboxApp: sandboxReviewVerified,
            hasVerifiedSandboxPurchase: hasSandboxReviewPurchase) { return reviewAccess }
        return LegacyLocalAccessPolicy.workspaceAccess(
            enforcementEnabled: BillingReleaseConfiguration.localAccessEnforcementEnabled,
            decision: legacyLocalDecision, hasProductionPurchase: hasProductionLocalPurchase)
    }
    private(set) var isBusy = false
    private(set) var message = ""
    let salesEnabled: Bool
    private let sandboxOnly: Bool
    private let cloudVerifier: CloudVerifier?
    private let cloudPurchasePreflight: CloudPurchasePreflight?
    private var accountID: UUID?
    @ObservationIgnored private var listener: Task<Void, Never>?

    init(salesEnabled: Bool = false, cloudVerifier: CloudVerifier? = nil, cloudPurchasePreflight: CloudPurchasePreflight? = nil,
         sandboxOnly: Bool = BillingReleaseConfiguration.sandboxOnlyBuild) {
        self.salesEnabled = salesEnabled
        self.cloudVerifier = cloudVerifier
        self.cloudPurchasePreflight = cloudPurchasePreflight
        self.sandboxOnly = sandboxOnly
    }

    deinit { listener?.cancel() }

    func load(accountID: UUID? = nil) async {
        self.accountID = accountID
        legacyLocalDecision = BillingReleaseConfiguration.firstPaidLocalBuild == nil ? .notConfigured : .evidenceUnavailable
        message = ""
        if listener == nil {
            listener = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self else { return }
                    if case .verified(let transaction) = result {
                        guard BillingReleaseConfiguration.permitsReviewProduct(transaction.productID,
                            verifiedSandbox: transaction.environment == .sandbox) else { continue }
                        if StoreProductCatalog.isCloud(transaction.productID),
                           transaction.appAccountToken != self.accountID || self.cloudVerifier == nil { continue }
                    }
                    // Pending cloud transactions remain unfinished until server validation succeeds.
                    do { try await self.deliver(result) } catch { self.message = error.localizedDescription }
                    await self.refreshLocalEntitlement()
                }
            }
        }
        do {
            products = try await Product.products(for: StoreProductCatalog.all)
                .sorted { (StoreProductCatalog.all.firstIndex(of: $0.id) ?? Int.max) < (StoreProductCatalog.all.firstIndex(of: $1.id) ?? Int.max) }
            if products.isEmpty { message = AppLocalization.text("购买暂未开放。已有业务资料不受影响。") }
        } catch { message = AppLocalization.text("暂时无法读取商店商品，请稍后重试。") }
        await refreshLocalEntitlement()
        await refreshLegacyLocalEvidence()
        await retryUnfinishedTransactions()
    }

    func canPurchase(_ product: Product) -> Bool {
        salesEnabled && StoreProductCatalog.all.contains(product.id)
            && BillingReleaseConfiguration.permitsReviewProduct(product.id, verifiedSandbox: sandboxReviewVerified)
            && (product.id != StoreProductCatalog.local || LegacyLocalAccessPolicy.allowsLocalPurchase(
                decision: legacyLocalDecision, hasPurchase: hasLocalPurchase,
                cutoverConfigured: BillingReleaseConfiguration.firstPaidLocalBuild != nil && !sandboxReviewVerified))
            && (!StoreProductCatalog.isCloud(product.id) || (cloudVerifier != nil && cloudPurchasePreflight != nil && accountID != nil))
    }

    func purchase(_ product: Product) async {
        guard !isBusy else { return }
        guard canPurchase(product) else { message = AppLocalization.text("购买暂未开放。"); return }
        isBusy = true; message = ""
        defer { isBusy = false }
        do {
            try await checkStoreEnvironment()
            if StoreProductCatalog.isCloud(product.id) {
                guard let expectedID = accountID, let cloudPurchasePreflight else { throw PurchaseFailure.cloudNotConfigured }
                try await cloudPurchasePreflight(expectedID)
                guard accountID == expectedID else { throw PurchaseFailure.cloudNotConfigured }
            }
            let options: Set<Product.PurchaseOption> = StoreProductCatalog.isCloud(product.id)
                ? [.appAccountToken(accountID!)] : []
            switch try await product.purchase(options: options) {
            case .success(let result):
                try await deliver(result)
                await refreshLocalEntitlement()
                message = AppLocalization.text("购买已验证。")
            case .pending: message = AppLocalization.text("购买正在等待批准，批准后会自动处理。")
            case .userCancelled: message = AppLocalization.text("购买已取消。")
            @unknown default: message = AppLocalization.text("购买状态尚未确认，请稍后恢复购买。")
            }
        } catch { message = error.localizedDescription }
    }

    #if DEBUG && STOREKIT_SANDBOX_ACCEPTANCE
    private(set) var sandboxRefundDiagnostic = ""
    var canRequestSandboxRefund: Bool {
        sandboxOnly && accountID == SandboxRefundPolicy.lifecycleOwner && cloudPurchasePreflight != nil
    }
    func refreshSandboxRefundDiagnostic() async {
        await requestSandboxRefund(in: nil)
    }
    func requestSandboxRefund(in scene: UIWindowScene?) async {
        guard !isBusy, canRequestSandboxRefund, let owner = accountID, let preflight = cloudPurchasePreflight else { return }
        isBusy = true; message = ""; sandboxRefundDiagnostic = ""
        defer { isBusy = false }
        do {
            try await checkStoreEnvironment()
            try await preflight(owner)
            var candidate: Transaction?
            var scanned = 0, verified = 0, sandbox = 0, matched = 0, eligible = 0
            for await result in Transaction.all {
                scanned += 1
                guard case .verified(let transaction) = result else { continue }
                verified += 1
                if transaction.environment == .sandbox { sandbox += 1 }
                if transaction.environment == .sandbox, transaction.appAccountToken == owner,
                   StoreProductCatalog.isCloud(transaction.productID) { matched += 1 }
                guard SandboxRefundPolicy.permits(buildEnabled: BillingReleaseConfiguration.sandboxAcceptanceBuild,
                        owner: owner, transactionOwner: transaction.appAccountToken, product: transaction.productID,
                        environment: transaction.environment, revoked: transaction.revocationDate != nil,
                        upgraded: transaction.isUpgraded) else { continue }
                eligible += 1
                if candidate == nil || transaction.purchaseDate > candidate!.purchaseDate { candidate = transaction }
            }
            guard !Task.isCancelled, accountID == owner, canRequestSandboxRefund else { return }
            sandboxRefundDiagnostic = AppLocalization.format("历史 %ld · 已验证 %ld · 沙盒 %ld · 本账号 %ld · 可申请 %ld", scanned, verified, sandbox, matched, eligible)
            guard let candidate else {
                message = AppLocalization.text("未找到属于当前账号的可退款沙盒交易。"); return
            }
            // A diagnostic-only read never presents Apple UI or changes a transaction.
            guard let scene else { return }
            try await preflight(owner)
            guard accountID == owner, canRequestSandboxRefund else { return }
            let result = try await candidate.beginRefundRequest(in: scene)
            try await preflight(owner)
            switch result {
            case .success: message = AppLocalization.text("退款请求已提交，等待 Apple 通知确认。")
            case .userCancelled: message = AppLocalization.text("已取消")
            @unknown default: message = AppLocalization.text("退款状态尚未确认，请稍后检查。")
            }
        } catch { message = error.localizedDescription }
    }
    #endif

    func restore() async {
        guard !isBusy else { return }
        legacyLocalDecision = BillingReleaseConfiguration.firstPaidLocalBuild == nil ? .notConfigured : .evidenceUnavailable
        isBusy = true; message = ""
        defer { isBusy = false }
        do {
            try await checkStoreEnvironment()
            try await AppStore.sync()
            var restoredCloud = false
            var cloudNeedsConfiguration = false
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result,
                      BillingReleaseConfiguration.permitsReviewProduct(transaction.productID,
                        verifiedSandbox: transaction.environment == .sandbox) else { continue }
                if StoreProductCatalog.isCloud(transaction.productID), cloudVerifier == nil || accountID == nil {
                    cloudNeedsConfiguration = true
                }
                if StoreProductCatalog.isCloud(transaction.productID), cloudVerifier != nil,
                   let accountID, transaction.appAccountToken == accountID {
                    try await deliver(result)
                    if StoreProductCatalog.isActive(productID: transaction.productID,
                        revokedAt: transaction.revocationDate, expiresAt: transaction.expirationDate,
                        upgraded: transaction.isUpgraded) { restoredCloud = true }
                }
            }
            await refreshLocalEntitlement()
            await refreshLegacyLocalEvidence()
            let restoredLocal = accountID == nil && (hasLocalPurchase || legacyLocalDecision.grantsLegacyLocalAccess)
            if restoredLocal || restoredCloud {
                message = AppLocalization.text("已恢复可用的购买权益。")
            } else if cloudNeedsConfiguration {
                message = AppLocalization.text("未找到可恢复的购买。云端订阅恢复需完成账号和服务端验证配置。")
            } else {
                message = AppLocalization.text("未找到可恢复的有效购买。订阅可能已到期或退款。")
            }
        } catch { message = error.localizedDescription }
    }

    private func refreshLegacyLocalEvidence() async {
        legacyLocalDecision = await LegacyLocalAccessReader.decision(
            expectedBundleID: "com.yunshengtech.travelmanager",
            firstPaidBuild: BillingReleaseConfiguration.firstPaidLocalBuild)
    }

    /// Read evidence only; no product requests, cloud delivery, or new payment.
    func refreshLocalAccessEvidence() async {
        await refreshLocalEntitlement()
        await refreshLegacyLocalEvidence()
    }

    private func refreshLocalEntitlement() async {
        var active = false
        var productionActive = false
        var sandboxActive = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productID == StoreProductCatalog.local,
                  StoreProductCatalog.isActive(productID: transaction.productID, revokedAt: transaction.revocationDate,
                                               expiresAt: transaction.expirationDate, upgraded: transaction.isUpgraded) else { continue }
            if BillingReleaseConfiguration.permits(environment: transaction.environment, sandboxOnly: sandboxOnly) { active = true }
            if transaction.environment == .production { productionActive = true }
            if transaction.environment == .sandbox { sandboxActive = true }
        }
        sandboxReviewVerified = false
        if BillingReleaseConfiguration.reviewBuild || BillingReleaseConfiguration.paidReleaseBuild {
            sandboxReviewVerified = await LegacyLocalAccessReader.hasVerifiedSandboxApp(
                expectedBundleID: "com.yunshengtech.travelmanager")
        }
        hasSandboxReviewPurchase = sandboxReviewVerified && sandboxActive
        if BillingReleaseConfiguration.localReviewBuild || (BillingReleaseConfiguration.paidReleaseBuild && sandboxReviewVerified) {
            hasLocalPurchase = hasSandboxReviewPurchase
        } else {
            hasLocalPurchase = BillingReleaseConfiguration.paidReleaseBuild ? productionActive : active
        }
        hasProductionLocalPurchase = productionActive
    }

    private func checkStoreEnvironment() async throws {
        if BillingReleaseConfiguration.paidReleaseBuild {
            _ = try await Self.verifiedPaidEnvironment()
        } else if sandboxOnly || BillingReleaseConfiguration.reviewBuild {
            guard case .verified(let app) = try await AppTransaction.shared,
                  app.bundleID == Bundle.main.bundleIdentifier, app.environment == .sandbox else {
                throw PurchaseFailure.sandboxRequired
            }
        }
    }

    static func verifiedPaidEnvironment() async throws -> AppStore.Environment {
        guard case .verified(let app) = try await AppTransaction.shared,
              app.bundleID == "com.yunshengtech.travelmanager",
              app.bundleID == Bundle.main.bundleIdentifier,
              app.environment == .production || app.environment == .sandbox else {
            throw PurchaseFailure.unverified
        }
        return app.environment
    }

    private func retryUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result,
                  StoreProductCatalog.all.contains(transaction.productID),
                  BillingReleaseConfiguration.permitsReviewProduct(transaction.productID,
                    verifiedSandbox: transaction.environment == .sandbox) else { continue }
            if StoreProductCatalog.isCloud(transaction.productID) {
                guard cloudVerifier != nil, let accountID, transaction.appAccountToken == accountID else { continue }
            }
            do { try await deliver(result) }
            catch { message = error.localizedDescription }
        }
    }

    private func deliver(_ result: VerificationResult<Transaction>) async throws {
        guard case .verified(let transaction) = result else { throw PurchaseFailure.unverified }
        if BillingReleaseConfiguration.paidReleaseBuild {
            let environment = try await Self.verifiedPaidEnvironment()
            guard transaction.environment == environment else { throw PurchaseFailure.unverified }
        }
        if BillingReleaseConfiguration.reviewBuild {
            try await checkStoreEnvironment()
            guard BillingReleaseConfiguration.permitsReviewProduct(transaction.productID,
                verifiedSandbox: transaction.environment == .sandbox) else { throw PurchaseFailure.sandboxRequired }
        }
        guard BillingReleaseConfiguration.permits(environment: transaction.environment, sandboxOnly: sandboxOnly) else {
            throw PurchaseFailure.sandboxRequired
        }
        guard StoreProductCatalog.all.contains(transaction.productID) else { return }
        if StoreProductCatalog.isCloud(transaction.productID) {
            guard let accountID, transaction.appAccountToken == accountID, let cloudVerifier else { throw PurchaseFailure.cloudNotConfigured }
            // Forward verified revocation/expiry events too; the server decides the resulting grant.
            try await cloudVerifier(result.jwsRepresentation, accountID)
            guard self.accountID == accountID else { throw PurchaseFailure.cloudNotConfigured }
        } else {
            await refreshLocalEntitlement()
        }
        await transaction.finish()
    }

    private enum PurchaseFailure: LocalizedError {
        case unverified, cloudNotConfigured, sandboxRequired
        var errorDescription: String? {
            switch self {
            case .unverified: AppLocalization.text("购买签名未通过验证，没有变更权限。")
            case .cloudNotConfigured: AppLocalization.text("云端购买尚未完成账号与服务端验证，交易已保留，请稍后重试。")
            case .sandboxRequired: AppLocalization.text("此测试版本仅接受Apple沙盒环境，请勿进行正式付款。")
            }
        }
    }
}
