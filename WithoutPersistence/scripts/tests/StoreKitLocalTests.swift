import XCTest
import StoreKit
import StoreKitTest

final class StoreKitLocalIntegrationTests: XCTestCase {
    @MainActor private func session() throws -> SKTestSession {
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TrvelMA", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: config)
        session.resetToDefaultState()
        session.askToBuyEnabled = false
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    @MainActor func testLocalPurchaseRestoreAndRefund() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = StorePurchaseManager()
        await store.load()
        XCTAssertEqual(Set(store.products.map(\.id)), Set(StoreProductCatalog.all))
        XCTAssertFalse(store.hasLocalPurchase)
        XCTAssertFalse(store.salesEnabled)
        let transaction = try await session.buyProduct(identifier: StoreProductCatalog.local)
        await store.load()
        XCTAssertTrue(store.hasLocalPurchase)
        XCTAssertFalse(store.hasProductionLocalPurchase, "Xcode StoreKit purchase cannot prove a production buyout")
        XCTAssertEqual(store.localWorkspaceAccess, .unchanged, "Release gate remains disabled during acceptance")
        await store.restore()
        XCTAssertTrue(store.hasLocalPurchase)
        XCTAssertFalse(store.hasProductionLocalPurchase, "Restoring test purchases cannot grant production access")
        try session.refundTransaction(identifier: UInt(transaction.id))
        for _ in 0..<20 {
            await store.load()
            if !store.hasLocalPurchase { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(store.hasLocalPurchase)
    }

    @MainActor func testCloudProductCannotBePurchasedWithoutServerVerifier() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = StorePurchaseManager(salesEnabled: true)
        await store.load(accountID: UUID())
        let product = try XCTUnwrap(store.products.first { $0.id == StoreProductCatalog.monthly })
        XCTAssertFalse(store.canPurchase(product))
        await store.purchase(product)
        XCTAssertEqual(try session.allTransactions().count, 0)
    }
}

extension StoreKitLocalIntegrationTests {
    @MainActor func testEmptyRestoreDoesNotClaimServerConfigurationIsMissing() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = StorePurchaseManager()
        await store.restore()
        XCTAssertFalse(store.hasLocalPurchase)
        XCTAssertEqual(store.message, AppLocalization.text("未找到可恢复的有效购买。订阅可能已到期或退款。"))
        XCTAssertTrue(try session.allTransactions().isEmpty)
    }

    @MainActor func testCloudPurchaseRequiresPreflightEvenWithVerifier() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = StorePurchaseManager(salesEnabled: true, cloudVerifier: { _, _ in })
        await store.load(accountID: UUID())
        let product = try XCTUnwrap(store.products.first { $0.id == StoreProductCatalog.monthly })
        XCTAssertFalse(store.canPurchase(product))
        await store.purchase(product)
        XCTAssertTrue(try session.allTransactions().isEmpty)
    }

    @MainActor func testFailedCloudPreflightDoesNotStartPayment() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let owner = UUID()
        var deliveries = 0
        let store = StorePurchaseManager(salesEnabled: true, cloudVerifier: { _, _ in deliveries += 1 }, cloudPurchasePreflight: { id in
            XCTAssertEqual(id, owner)
            throw NSError(domain: "PreflightFixture", code: 1)
        })
        await store.load(accountID: owner)
        let product = try XCTUnwrap(store.products.first { $0.id == StoreProductCatalog.monthly })
        await store.purchase(product)
        XCTAssertTrue(try session.allTransactions().isEmpty)
        XCTAssertEqual(deliveries, 0)
    }

    @MainActor func testCloudPaymentPreflightRunsBeforeDeliveryAndBindsOwner() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let owner = UUID()
        var preflightPassed = false
        var delivered = false
        let store = StorePurchaseManager(salesEnabled: true, cloudVerifier: { _, id in
            XCTAssertTrue(preflightPassed)
            XCTAssertEqual(id, owner)
            delivered = true
        }, cloudPurchasePreflight: { id in
            XCTAssertEqual(id, owner)
            preflightPassed = true
        })
        await store.load(accountID: owner)
        let product = try XCTUnwrap(store.products.first { $0.id == StoreProductCatalog.monthly })
        await store.purchase(product)
        XCTAssertTrue(delivered, store.message)
        XCTAssertEqual(store.message, AppLocalization.text("购买已验证。"))
        let transactions = try session.allTransactions()
        XCTAssertEqual(transactions.count, 1)
    }

    @MainActor func testUnfinishedCloudTransactionRetriesOnReloadAfterServerRecovery() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let owner = UUID()
        let transaction = try await session.buyProduct(identifier: StoreProductCatalog.monthly, options: [.appAccountToken(owner)])
        var unavailable = true
        var successfulDeliveries = 0
        let store = StorePurchaseManager(cloudVerifier: { _, id in
            XCTAssertEqual(id, owner)
            if unavailable { throw NSError(domain: "ServerUnavailableFixture", code: 503) }
            successfulDeliveries += 1
        })
        await store.load(accountID: owner)
        XCTAssertFalse(store.message.isEmpty)
        var before = Set<UInt64>()
        for await result in Transaction.unfinished {
            if case .verified(let tx) = result { before.insert(tx.id) }
        }
        XCTAssertTrue(before.contains(transaction.id))
        unavailable = false
        await store.load(accountID: owner)
        XCTAssertEqual(store.message, "", "A recovered server must not leave the previous failure visible")
        var after = Set<UInt64>()
        for await result in Transaction.unfinished {
            if case .verified(let tx) = result { after.insert(tx.id) }
        }
        XCTAssertGreaterThan(successfulDeliveries, 0)
        XCTAssertFalse(after.contains(transaction.id))
    }

    @MainActor func testAccountSwitchDuringPreflightDoesNotStartPayment() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        var switchAccount: (() async -> Void)?
        let store = StorePurchaseManager(salesEnabled: true, cloudVerifier: { _, _ in
            XCTFail("Payment must not reach delivery after account switching")
        }, cloudPurchasePreflight: { _ in await switchAccount?() })
        await store.load(accountID: UUID())
        switchAccount = { [weak store] in await store?.load(accountID: UUID()) }
        let product = try XCTUnwrap(store.products.first { $0.id == StoreProductCatalog.monthly })
        await store.purchase(product)
        XCTAssertTrue(try session.allTransactions().isEmpty)
    }

    @MainActor func testRepeatedPurchaseDuringPreflightDoesNotChangeStatusOrChargeTwice() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let entered = expectation(description: "Purchase preflight entered")
        var release: CheckedContinuation<Void, Never>?
        let store = StorePurchaseManager(salesEnabled: true, cloudVerifier: { _, _ in }, cloudPurchasePreflight: { _ in
            await withCheckedContinuation { continuation in
                release = continuation
                entered.fulfill()
            }
        })
        await store.load(accountID: UUID())
        let product = try XCTUnwrap(store.products.first { $0.id == StoreProductCatalog.monthly })
        let first = Task { await store.purchase(product) }
        await fulfillment(of: [entered], timeout: 3)
        await store.purchase(product)
        XCTAssertEqual(store.message, "")
        XCTAssertTrue(store.isBusy)
        XCTAssertTrue(try session.allTransactions().isEmpty)
        let continuation = try XCTUnwrap(release)
        continuation.resume()
        await first.value
        XCTAssertEqual(try session.allTransactions().count, 1)
        XCTAssertEqual(store.message, AppLocalization.text("购买已验证。"))
    }

    @MainActor func testForeignAccountUnfinishedTransactionIsNotConsumed() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: StoreProductCatalog.monthly, options: [.appAccountToken(UUID())])
        var deliveries = 0
        let store = StorePurchaseManager(cloudVerifier: { _, _ in deliveries += 1 })
        await store.load(accountID: UUID())
        await store.restore()
        var unfinished = Set<UInt64>()
        for await result in Transaction.unfinished {
            if case .verified(let tx) = result { unfinished.insert(tx.id) }
        }
        XCTAssertEqual(deliveries, 0)
        XCTAssertTrue(unfinished.contains(transaction.id))
    }

    @MainActor func testForeignCloudSubscriptionDoesNotBlockLocalRestore() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        _ = try await session.buyProduct(identifier: StoreProductCatalog.monthly, options: [.appAccountToken(UUID())])
        _ = try await session.buyProduct(identifier: StoreProductCatalog.local)
        let store = StorePurchaseManager(cloudVerifier: { _, _ in XCTFail("Foreign account must never be delivered") })
        await store.load(accountID: UUID())
        await store.restore()
        XCTAssertTrue(store.hasLocalPurchase)
        XCTAssertEqual(store.message, AppLocalization.text("已恢复可用的购买权益。"))
    }

    @MainActor func testClientPurchaseFlowGrantsLocalEntitlement() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = StorePurchaseManager(salesEnabled: true)
        await store.load()
        let local = try XCTUnwrap(store.products.first { $0.id == StoreProductCatalog.local })
        await store.purchase(local)
        XCTAssertTrue(store.hasLocalPurchase, store.message)
        XCTAssertEqual(store.message, AppLocalization.text("购买已验证。"))
    }

    @MainActor func testPendingApprovalDoesNotGrantBeforeApproval() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        session.askToBuyEnabled = true
        let store = StorePurchaseManager(salesEnabled: true)
        await store.load()
        let local = try XCTUnwrap(store.products.first { $0.id == StoreProductCatalog.local })
        await store.purchase(local)
        XCTAssertFalse(store.hasLocalPurchase)
        XCTAssertEqual(store.message, AppLocalization.text("购买正在等待批准，批准后会自动处理。"))
        let transaction = try XCTUnwrap(try session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: transaction.identifier)
        for _ in 0..<20 {
            await store.load()
            if store.hasLocalPurchase { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(store.hasLocalPurchase)
    }

    @MainActor func testCloudRestoreVerifiesMatchingAccountAndRejectsDifferentAccount() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let owner = UUID()
        let transaction = try await session.buyProduct(identifier: StoreProductCatalog.monthly, options: [.appAccountToken(owner)])
        var verifiedTransactionIDs = Set<String>()
        let correct = StorePurchaseManager(cloudVerifier: { jws, account in
            XCTAssertFalse(jws.isEmpty); XCTAssertEqual(account, owner)
            // Updates and explicit restore may deliver the same verified transaction.
            // Assert transaction identity, not a single callback delivery.
            let parts = jws.split(separator: ".")
            let payloadPart = try XCTUnwrap(parts.count > 1 ? String(parts[1]) : nil)
            var base64 = payloadPart.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
            let payloadData = try XCTUnwrap(Data(base64Encoded: base64))
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: payloadData) as? [String: Any])
            let receivedID = try XCTUnwrap(payload["transactionId"] as? String)
            XCTAssertEqual(receivedID, String(transaction.id))
            verifiedTransactionIDs.insert(receivedID)
        })
        await correct.load(accountID: owner)
        await correct.restore()
        XCTAssertEqual(verifiedTransactionIDs, [String(transaction.id)])
        XCTAssertEqual(correct.message, AppLocalization.text("已恢复可用的购买权益。"))
        var incorrect = 0
        let other = StorePurchaseManager(cloudVerifier: { _, _ in incorrect += 1 })
        await other.load(accountID: UUID())
        await other.restore()
        XCTAssertEqual(incorrect, 0)
        XCTAssertFalse(other.hasLocalPurchase)
    }
}


extension StoreKitLocalIntegrationTests {
    @MainActor func testOwnedLocalProductCannotStartAnotherPurchase() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = StorePurchaseManager(salesEnabled: true)
        await store.load()
        let product = try XCTUnwrap(store.products.first { $0.id == StoreProductCatalog.local })
        await store.purchase(product)
        XCTAssertTrue(store.hasLocalPurchase)
        XCTAssertFalse(store.canPurchase(product))
        let count = try session.allTransactions().count
        await store.purchase(product)
        XCTAssertEqual(try session.allTransactions().count, count)
        try session.refundTransaction(identifier: try XCTUnwrap(try session.allTransactions().first).identifier)
        await store.load()
        XCTAssertFalse(store.hasLocalPurchase)
        XCTAssertTrue(store.canPurchase(product))
    }

    @MainActor func testFreshManagerRestoresLocalPurchaseWithoutGrantingCloudAccess() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        _ = try await session.buyProduct(identifier: StoreProductCatalog.local)
        let fresh = StorePurchaseManager(salesEnabled: true)
        await fresh.load()
        await fresh.restore()
        XCTAssertTrue(fresh.hasLocalPurchase)
        let auth = AuthViewModel()
        XCTAssertFalse(auth.isCloudAccount)
        XCTAssertFalse(auth.canQueryFlights)
        XCTAssertFalse(auth.canUseCurrentCloudEdition)
    }
}


extension StoreKitLocalIntegrationTests {
    @MainActor func testAccountSwitchDuringVerificationLeavesTransactionUnfinished() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let owner = UUID(), other = UUID()
        var switchAccount: (() async -> Void)?
        let store = StorePurchaseManager(salesEnabled: true, cloudVerifier: { _, id in
            XCTAssertEqual(id, owner)
            await switchAccount?()
        }, cloudPurchasePreflight: { _ in })
        await store.load(accountID: owner)
        switchAccount = { [weak store] in await store?.load(accountID: other) }
        let product = try XCTUnwrap(store.products.first { $0.id == StoreProductCatalog.monthly })
        await store.purchase(product)
        XCTAssertNotEqual(store.message, AppLocalization.text("购买已验证。"))
        var matching = 0
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result, transaction.appAccountToken == owner { matching += 1 }
        }
        XCTAssertGreaterThan(matching, 0)
        XCTAssertFalse(store.hasLocalPurchase)
    }
}
