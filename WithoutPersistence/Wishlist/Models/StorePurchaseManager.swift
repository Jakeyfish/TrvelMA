import Foundation
import StoreKit
import Observation

enum BillingReleaseConfiguration {
    // Explicit developer build only. Release cannot enable this via build flags.
    #if DEBUG && STOREKIT_SANDBOX_ACCEPTANCE
    static let sandboxAcceptanceBuild = true
    static let sandboxOwnerID = UUID(uuidString: "71b164e4-7dbf-4433-8503-84ed156171de")!
    #else
    static let sandboxAcceptanceBuild = false
    static let sandboxOwnerID: UUID? = nil
    #endif
    static let salesEnabled = sandboxAcceptanceBuild
    static let plansVisible = sandboxAcceptanceBuild

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

/// Cloud grants are deliberately injected only after server signature verification is deployed.
/// No UI setting or UserDefaults flag can enable production sales.
@MainActor @Observable final class StorePurchaseManager {
    typealias CloudVerifier = @MainActor (_ signedTransaction: String, _ accountID: UUID) async throws -> Void
    typealias CloudPurchasePreflight = @MainActor (_ accountID: UUID) async throws -> Void
    static let shared = StorePurchaseManager()
    private(set) var products: [Product] = []
    private(set) var hasLocalPurchase = false
    private(set) var isBusy = false
    private(set) var message = ""
    let salesEnabled: Bool
    private let sandboxOnly: Bool
    private let cloudVerifier: CloudVerifier?
    private let cloudPurchasePreflight: CloudPurchasePreflight?
    private var accountID: UUID?
    @ObservationIgnored private var listener: Task<Void, Never>?

    init(salesEnabled: Bool = false, cloudVerifier: CloudVerifier? = nil, cloudPurchasePreflight: CloudPurchasePreflight? = nil,
         sandboxOnly: Bool = BillingReleaseConfiguration.sandboxAcceptanceBuild) {
        self.salesEnabled = salesEnabled
        self.cloudVerifier = cloudVerifier
        self.cloudPurchasePreflight = cloudPurchasePreflight
        self.sandboxOnly = sandboxOnly
    }

    deinit { listener?.cancel() }

    func load(accountID: UUID? = nil) async {
        self.accountID = accountID
        message = ""
        if listener == nil {
            listener = Task { [weak self] in
                for await result in Transaction.updates {
                    guard let self else { return }
                    if case .verified(let transaction) = result,
                       StoreProductCatalog.isCloud(transaction.productID),
                       (transaction.appAccountToken != self.accountID || self.cloudVerifier == nil) { continue }
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
        await retryUnfinishedTransactions()
    }

    func canPurchase(_ product: Product) -> Bool {
        salesEnabled && StoreProductCatalog.all.contains(product.id)
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

    func restore() async {
        guard !isBusy else { return }
        isBusy = true; message = ""
        defer { isBusy = false }
        do {
            try await checkStoreEnvironment()
            try await AppStore.sync()
            var restoredCloud = false
            for await result in Transaction.currentEntitlements {
                guard case .verified(let transaction) = result else { continue }
                if StoreProductCatalog.isCloud(transaction.productID), cloudVerifier != nil,
                   let accountID, transaction.appAccountToken == accountID {
                    try await deliver(result); restoredCloud = true
                }
            }
            await refreshLocalEntitlement()
            message = hasLocalPurchase || restoredCloud ? AppLocalization.text("已恢复可用的购买权益。") : AppLocalization.text("未找到可恢复的购买。云端订阅恢复需完成账号和服务端验证配置。")
        } catch { message = error.localizedDescription }
    }

    private func refreshLocalEntitlement() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == StoreProductCatalog.local,
               BillingReleaseConfiguration.permits(environment: transaction.environment, sandboxOnly: sandboxOnly) {
                active = StoreProductCatalog.isActive(productID: transaction.productID, revokedAt: transaction.revocationDate, expiresAt: transaction.expirationDate, upgraded: transaction.isUpgraded)
            }
        }
        hasLocalPurchase = active
    }

    private func checkStoreEnvironment() async throws {
        guard sandboxOnly else { return }
        guard case .verified(let app) = try await AppTransaction.shared,
              BillingReleaseConfiguration.permits(environment: app.environment, sandboxOnly: true) else {
            throw PurchaseFailure.sandboxRequired
        }
    }

    private func retryUnfinishedTransactions() async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result,
                  StoreProductCatalog.all.contains(transaction.productID) else { continue }
            if StoreProductCatalog.isCloud(transaction.productID) {
                guard cloudVerifier != nil, let accountID, transaction.appAccountToken == accountID else { continue }
            }
            do { try await deliver(result) }
            catch { message = error.localizedDescription }
        }
    }

    private func deliver(_ result: VerificationResult<Transaction>) async throws {
        guard case .verified(let transaction) = result else { throw PurchaseFailure.unverified }
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
