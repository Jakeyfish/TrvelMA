import MapKit
import XCTest
import Foundation
import SwiftData
import UIKit
import SwiftUI
import CryptoKit
import StoreKit

final class NavigationDestinationRegressionTests: XCTestCase {
    @MainActor func testTextDestinationIsSearchNotAnUnverifiedRoute() throws {
        let previous = DataOwnership.activeScope
        let scope = "local:navigation-qa-" + UUID().uuidString
        DataOwnership.activateLocal(scope: scope)
        defer { NavigationDestinationStore.clear(scope: scope); DataOwnership.activateLocal(scope: previous) }
        let address = "123 QA Greenwood Ave 圣加百利, CA, 美国 #2 & North"
        for provider in NavigationProvider.allCases {
            let url = try XCTUnwrap(provider.directionsURL(for: address))
            let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(items.first { $0.name == (provider == .googleMaps ? "query" : "q") }?.value, address)
            XCTAssertFalse(items.contains { $0.name == "destination" || $0.name == "daddr" })
        }
    }
    @MainActor func testSelectedPointRoutesExactlyAndCannotLeakToAnotherAddressOrAccount() throws {
        let previous = DataOwnership.activeScope
        let scope = "local:navigation-qa-" + UUID().uuidString
        DataOwnership.activateLocal(scope: scope)
        defer { NavigationDestinationStore.clear(scope: scope); DataOwnership.activateLocal(scope: previous) }
        let address = "123 N QA Greenwood Ave"
        let point = NavigationPoint(latitude: 34.123456, longitude: -118.123456)
        NavigationDestinationStore.remember(point, for: address)
        for provider in NavigationProvider.allCases {
            let url = try XCTUnwrap(provider.directionsURL(for: address))
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == (provider == .googleMaps ? "destination" : "daddr") }?.value, point.queryValue)
        }
        XCTAssertNil(NavigationDestinationStore.point(for: "123 S QA Greenwood Ave"))
        XCTAssertNil(NavigationDestinationStore.point(for: address, scope: "cloud:other@example.invalid"))
        XCTAssertNil(NavigationProvider.googleMaps.directionsURL(for: " "))
    }
    @MainActor func testInvalidPointsAndAmbiguousSelectionDoNotBecomeRoutes() async {
        let previous = DataOwnership.activeScope
        let scope = "local:navigation-qa-" + UUID().uuidString
        DataOwnership.activateLocal(scope: scope)
        defer { NavigationDestinationStore.clear(scope: scope); DataOwnership.activateLocal(scope: previous) }
        let address = "QA ambiguous"
        for point in [NavigationPoint(latitude: .nan, longitude: 1), .init(latitude: 91, longitude: 1), .init(latitude: 1, longitude: 181)] {
            NavigationDestinationStore.remember(point, for: address)
            XCTAssertNil(NavigationDestinationStore.point(for: address))
        }
        let point = NavigationPoint(latitude: 34, longitude: -118)
        NavigationDestinationStore.remember(point, for: address)
        await NavigationDestinationStore.select(address: address) { [point, .init(latitude: 35, longitude: -118)] }.value
        XCTAssertNil(NavigationDestinationStore.point(for: address), "Do not choose the first ambiguous result or retain a stale point")
        await NavigationDestinationStore.select(address: address) { throw URLError(.notConnectedToInternet) }.value
        XCTAssertNil(NavigationDestinationStore.point(for: address))
    }
    @MainActor func testOlderSelectionCannotOverwriteNewerSelectionForSameText() async throws {
        let previous = DataOwnership.activeScope
        let scope = "local:navigation-qa-" + UUID().uuidString
        DataOwnership.activateLocal(scope: scope)
        defer { NavigationDestinationStore.clear(scope: scope); DataOwnership.activateLocal(scope: previous) }
        let started = expectation(description: "Old selected-place lookup started")
        var resume: CheckedContinuation<[NavigationPoint], Never>?
        let old = NavigationDestinationStore.select(address: "QA same label") {
            await withCheckedContinuation { resume = $0; started.fulfill() }
        }
        await fulfillment(of: [started], timeout: 3)
        let newer = NavigationPoint(latitude: 35, longitude: -119)
        await NavigationDestinationStore.select(address: "QA same label") { [newer] }.value
        try XCTUnwrap(resume).resume(returning: [.init(latitude: 34, longitude: -118)])
        await old.value
        XCTAssertEqual(NavigationDestinationStore.point(for: "QA same label"), newer)
    }
    @MainActor func testClearingCacheOrSwitchingAccountRejectsPendingResult() async throws {
        for clear in [false, true] {
            let previous = DataOwnership.activeScope
            let scope = "local:navigation-qa-" + UUID().uuidString
            DataOwnership.activateLocal(scope: scope)
            let started = expectation(description: "Selected-place lookup started")
            var resume: CheckedContinuation<[NavigationPoint], Never>?
            let pending = NavigationDestinationStore.select(address: "QA pending") {
                await withCheckedContinuation { resume = $0; started.fulfill() }
            }
            await fulfillment(of: [started], timeout: 3)
            if clear { NavigationDestinationStore.clear(scope: scope) }
            else { DataOwnership.activateLocal(scope: "local:other-qa") }
            try XCTUnwrap(resume).resume(returning: [.init(latitude: 34, longitude: -118)])
            await pending.value
            XCTAssertNil(NavigationDestinationStore.point(for: "QA pending", scope: scope))
            NavigationDestinationStore.clear(scope: scope); DataOwnership.activateLocal(scope: previous)
        }
    }
}

final class SandboxBillingBuildPolicyTests: XCTestCase {
    func testSandboxAllowlistIsExplicitAndAbsentFromNormalBuild() {
        let developer = UUID(uuidString: "71b164e4-7dbf-4433-8503-84ed156171de")!
        let lifecycle = UUID(uuidString: "86361373-d4ba-4fc6-8f38-420367b6484e")!
        #if (DEBUG && STOREKIT_SANDBOX_ACCEPTANCE) || STOREKIT_CLOUD_REVIEW
        XCTAssertEqual(BillingReleaseConfiguration.sandboxOwnerIDs, [developer, lifecycle])
        #else
        XCTAssertTrue(BillingReleaseConfiguration.sandboxOwnerIDs.isEmpty)
        #endif
        XCTAssertFalse(BillingReleaseConfiguration.sandboxOwnerIDs.contains(UUID()))
    }
    func testDefaultBuildDoesNotExposePurchases() {
        #if !STOREKIT_SANDBOX_ACCEPTANCE && !STOREKIT_CLOUD_REVIEW && !STOREKIT_LOCAL_REVIEW
        XCTAssertFalse(BillingReleaseConfiguration.sandboxAcceptanceBuild)
        XCTAssertFalse(BillingReleaseConfiguration.salesEnabled)
        XCTAssertFalse(BillingReleaseConfiguration.plansVisible)
        XCTAssertNil(BillingReleaseConfiguration.sandboxOwnerID)
        #endif
    }
    func testProductionLocalGateRemainsDisabledUntilAcceptance() {
        XCTAssertFalse(BillingReleaseConfiguration.localAccessEnforcementEnabled)
        XCTAssertNil(BillingReleaseConfiguration.firstPaidLocalBuild)
    }
    func testReviewProductsRequireMatchingModeAndVerifiedSandbox() {
        typealias Configuration = BillingReleaseConfiguration
        for productionProduct in StoreProductCatalog.all {
            XCTAssertFalse(Configuration.permitsReviewProduct(productionProduct,
                verifiedSandbox: false, localReview: true, cloudReview: true))
        }
        for subscription in [StoreProductCatalog.monthly, StoreProductCatalog.yearly] {
            XCTAssertFalse(Configuration.permitsReviewProduct(subscription,
                verifiedSandbox: true, localReview: true, cloudReview: false))
            XCTAssertTrue(Configuration.permitsReviewProduct(subscription,
                verifiedSandbox: true, localReview: true, cloudReview: true))
        }
        XCTAssertFalse(Configuration.permitsReviewProduct(StoreProductCatalog.local,
            verifiedSandbox: true, localReview: false, cloudReview: true))
        XCTAssertTrue(Configuration.permitsReviewProduct(StoreProductCatalog.local,
            verifiedSandbox: true, localReview: true, cloudReview: true))
        XCTAssertFalse(Configuration.permitsReviewProduct("unknown",
            verifiedSandbox: true, localReview: true, cloudReview: true))
    }
    func testSandboxOnlyPolicyRejectsProductionTransactions() {
        XCTAssertFalse(BillingReleaseConfiguration.permits(environment: .production, sandboxOnly: true))
    }
    func testSandboxOnlyPolicyRejectsLocalXcodeFixtures() {
        XCTAssertFalse(BillingReleaseConfiguration.permits(environment: .xcode, sandboxOnly: true))
    }
    func testSandboxOnlyPolicyAcceptsAppleSandbox() {
        XCTAssertTrue(BillingReleaseConfiguration.permits(environment: .sandbox, sandboxOnly: true))
    }
}

final class LocalAccountArchiveTests: XCTestCase {
    @MainActor func testExportIsScopedReadOnlyAndIncludesExpensesStopsAndReminders() throws {
        let previous = DataOwnership.activeScope
        let email = "local-archive-qa@example.invalid"
        let scope = DataOwnership.localScope(email: email)
        DataOwnership.activateLocal(scope: scope)
        defer { DataOwnership.activateLocal(scope: previous) }
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let own = TripBookingRecord(form: NewTripFormModel())
        own.customerName = "Archive QA"; own.price = 90; own.isPaid = false
        own.locationStops = ["QA stop"]
        own.expenseAdjustmentsJSON = "[{\"fixture\":\"preserve-expense\"}]"
        own.reminderEnabled = true; own.reminderDateTime = Date(timeIntervalSince1970: 1700000000)
        own.flightArrivalTerminal = "QA-T1"
        let other = TripBookingRecord(form: NewTripFormModel())
        other.ownerScope = "cloud:other@example.invalid"; other.customerName = "DO-NOT-EXPORT"
        let customer = Custumer(name: "Own customer", email: "qa@example.invalid", csource: "", type: 1)
        let good = Connect(connectlable: "电话", connecttype: "15550000100", customer: customer)
        let bad = Connect(connectlable: "电话", connecttype: "15550000999", customer: customer)
        bad.ownerScope = other.ownerScope
        customer.connecttype = [good, bad]
        let goodAddress = Address(addlable: "QA", addresses: "Own address", customer: customer)
        let badAddress = Address(addlable: "Other", addresses: "DO-NOT-EXPORT", customer: customer)
        badAddress.ownerScope = other.ownerScope
        customer.addresses = [goodAddress, badAddress]
        own.customerUUID = customer.uuid
        context.insert(own); context.insert(other); context.insert(customer)
        try context.save()
        let archive = try LocalAccountArchive.snapshot(context: context, email: email)
        let trips = try XCTUnwrap(archive["trips"] as? [[String: Any]])
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?["price"] as? Double, 90)
        XCTAssertEqual(trips.first?["is_paid"] as? Bool, false)
        XCTAssertEqual(trips.first?["location_stop"] as? String, "QA stop")
        XCTAssertEqual(trips.first?["expense_adjustments_json"] as? String, own.expenseAdjustmentsJSON)
        XCTAssertEqual(trips.first?["reminder_enabled"] as? Bool, true)
        XCTAssertEqual(trips.first?["flight_arrival_terminal"] as? String, "QA-T1")
        let text = String(decoding: try JSONSerialization.data(withJSONObject: archive), as: UTF8.self)
        XCTAssertTrue(text.contains("15550000100")); XCTAssertFalse(text.contains("15550000999"))
        XCTAssertTrue(text.contains("Own address")); XCTAssertFalse(text.contains("DO-NOT-EXPORT"))
        XCTAssertFalse(context.hasChanges, "Export must not save, mutate or mark records paid")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TripBookingRecord>()), 2)
    }

    @MainActor func testExportRejectsWrongAccountAndCloudScope() throws {
        let previous = DataOwnership.activeScope
        defer { DataOwnership.activateLocal(scope: previous) }
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        DataOwnership.activateLocal(scope: DataOwnership.localScope(email: "owner-a@example.invalid"))
        XCTAssertThrowsError(try LocalAccountArchive.snapshot(context: context, email: "owner-b@example.invalid"))
        DataOwnership.activateCloud(email: "owner-a@example.invalid")
        XCTAssertThrowsError(try LocalAccountArchive.snapshot(context: context, email: "owner-a@example.invalid"))
    }
}

private final class SyncFixtureProtocol: URLProtocol {
    nonisolated(unsafe) static var handle: ((SyncFixtureProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let handler = Self.handle else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        handler(self)
    }
    override func stopLoading() {}
    nonisolated func respond(_ body: String, status: Int = 200) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class SyncRegressionTests: XCTestCase {
    @MainActor
    func runUpload(editDuringRequest: Bool, failAtEnd: Bool = false, cancelAtEnd: Bool = false, recoverAfterFailure: Bool = false) async throws {
        let oldScope = DataOwnership.activeScope
        let email = "isolated-sync-regression@example.invalid"
        DataOwnership.activateCloud(email: email)
        defer {
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        let schema = Schema(AppDataSchema.modelTypes)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let sentAt = Date(timeIntervalSince1970: 1700000000)
        let editedAt = sentAt.addingTimeInterval(60)
        let agency = TravelAgency(agencyCode: "QA", name: "Before upload", createdAt: sentAt, updateAt: sentAt)
        context.insert(agency)
        try context.save()
        var userRequests = 0
        var postedAgency = false
        var simulatedFailure = false
        var shouldFail = failAtEnd
        SyncFixtureProtocol.handle = { fixture in
            let path = fixture.request.url!.path
            if path == "/auth/v1/user" {
                userRequests += 1
                if shouldFail && userRequests > 1 {
                    simulatedFailure = true
                    if cancelAtEnd { fixture.client?.urlProtocol(fixture, didFailWithError: URLError(.cancelled)) }
                    else { fixture.respond("{}", status: 500) }
                }
                else { fixture.respond("{\"id\":\"00000000-0000-0000-0000-000000000001\"}") }
            } else if path == "/rest/v1/travel_agencies" && fixture.request.httpMethod == "POST" {
                postedAgency = true
                Task { @MainActor in
                    if editDuringRequest {
                        agency.name = "Edited while request is in flight"
                        agency.updateAt = editedAt
                        try context.save()
                    }
                    fixture.respond("[]")
                }
            } else { fixture.respond("[]") }
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        if failAtEnd {
            do {
                _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
                XCTFail("Expected the final mocked request to fail")
            } catch {
                XCTAssertTrue(simulatedFailure, "The expected late network failure must be reached")
                XCTAssertNil(agency.syncBaseUpdatedAt, "A partial failure must not acknowledge the version")
                if cancelAtEnd { XCTAssertEqual((error as? URLError)?.code, .cancelled) }
            }
            if recoverAfterFailure {
                shouldFail = false
                _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
                XCTAssertEqual(agency.name, "Edited while request is in flight")
                XCTAssertEqual(agency.syncBaseUpdatedAt, editedAt, "A retry must acknowledge the retained edit")
            }
        } else {
            _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
            XCTAssertEqual(agency.syncBaseUpdatedAt, sentAt)
            if editDuringRequest {
                XCTAssertEqual(agency.name, "Edited while request is in flight")
                XCTAssertEqual(agency.updateAt, editedAt)
                XCTAssertGreaterThan(agency.updateAt, try XCTUnwrap(agency.syncBaseUpdatedAt), "The new local edit must remain dirty")
            }
        }
        XCTAssertTrue(postedAgency, "The fixture must actually reach the production upload request")
    }
    @MainActor func testInFlightEditRemainsUnsynced() async throws { try await runUpload(editDuringRequest: true) }
    @MainActor func testUnchangedUploadAcknowledgesSentVersion() async throws { try await runUpload(editDuringRequest: false) }
    @MainActor func testPartialFailureDoesNotAdvanceBaseline() async throws { try await runUpload(editDuringRequest: true, failAtEnd: true) }
    @MainActor func testCancelledRequestRetainsEditAndRetrySucceeds() async throws {
        try await runUpload(editDuringRequest: true, failAtEnd: true, cancelAtEnd: true, recoverAfterFailure: true)
    }
    @MainActor func testNetworkFailureRetainsEditAndRetrySucceeds() async throws {
        try await runUpload(editDuringRequest: true, failAtEnd: true, recoverAfterFailure: true)
    }
    @MainActor
    func runMerge(localChanged: Bool, remoteDeleted: Bool, resolveKeepingRemote: Bool? = nil) async throws {
        let oldScope = DataOwnership.activeScope
        let email = "isolated-sync-conflict@example.invalid"
        DataOwnership.activateCloud(email: email)
        defer {
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        let schema = Schema(AppDataSchema.modelTypes)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let baseline = Date(timeIntervalSince1970: 1700000000)
        let localDate = localChanged ? baseline.addingTimeInterval(60) : baseline
        let remoteDate = baseline.addingTimeInterval(120)
        let agency = TravelAgency(agencyCode: "QA", name: "Local version", createdAt: baseline,
                                  updateAt: localDate, syncBaseUpdatedAt: baseline)
        context.insert(agency)
        try context.save()
        let remote: [[String: Any]] = [[
            "id": agency.uuid, "owner_id": "00000000-0000-0000-0000-000000000001",
            "agency_code": "QA", "name": "Remote version",
            "created_at": ISO8601DateFormatter().string(from: baseline),
            "updated_at": ISO8601DateFormatter().string(from: remoteDate),
            "deleted_at": remoteDeleted ? ISO8601DateFormatter().string(from: remoteDate) as Any : NSNull()
        ]]
        let remoteJSON = String(decoding: try JSONSerialization.data(withJSONObject: remote), as: UTF8.self)
        var postedAgency = false
        SyncFixtureProtocol.handle = { fixture in
            let path = fixture.request.url!.path
            if path == "/auth/v1/user" {
                fixture.respond("{\"id\":\"00000000-0000-0000-0000-000000000001\"}")
            } else if path == "/rest/v1/travel_agencies" && fixture.request.httpMethod == "GET" {
                fixture.respond(remoteJSON)
            } else {
                if path == "/rest/v1/travel_agencies" && fixture.request.httpMethod == "POST" { postedAgency = true }
                fixture.respond("[]")
            }
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
        let conflicts = try context.fetch(FetchDescriptor<CloudSyncConflict>())
        let records = try context.fetch(FetchDescriptor<TravelAgency>())
        XCTAssertEqual(records.count, 1)
        if localChanged {
            XCTAssertEqual(conflicts.count, 1)
            XCTAssertEqual(conflicts.first?.isRemoteDeletion, remoteDeleted)
            XCTAssertEqual(agency.name, "Local version", "A conflict must not silently overwrite the local edit")
            XCTAssertEqual(agency.syncBaseUpdatedAt, baseline)
            XCTAssertFalse(postedAgency, "Unresolved conflicts must be excluded from upload")
            if let keepRemote = resolveKeepingRemote {
                try SupabaseDataSync.resolveConflict(try XCTUnwrap(conflicts.first), keepRemote: keepRemote, context: context)
                XCTAssertTrue(try context.fetch(FetchDescriptor<CloudSyncConflict>()).isEmpty)
                if keepRemote {
                    XCTAssertEqual(agency.name, "Remote version")
                    XCTAssertEqual(agency.updateAt, remoteDate)
                } else {
                    XCTAssertGreaterThan(agency.updateAt, remoteDate, "Keeping local must create a new version after the remote baseline")
                    postedAgency = false
                    _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
                    XCTAssertEqual(agency.name, "Local version", "The next sync must preserve the explicitly chosen local version")
                    XCTAssertTrue(postedAgency)
                }
            }
        } else {
            XCTAssertTrue(conflicts.isEmpty)
            XCTAssertEqual(agency.name, "Remote version")
            XCTAssertEqual(agency.syncBaseUpdatedAt, remoteDate)
            XCTAssertTrue(postedAgency)
        }
    }
    @MainActor func testConcurrentEditsBecomeConflictWithoutOverwrite() async throws {
        try await runMerge(localChanged: true, remoteDeleted: false)
    }
    @MainActor func testRemoteDeletionPreservesConcurrentLocalEdit() async throws {
        try await runMerge(localChanged: true, remoteDeleted: true)
    }
    @MainActor func testCleanLocalRecordAcceptsRemoteUpdate() async throws {
        try await runMerge(localChanged: false, remoteDeleted: false)
    }

    @MainActor func testKeepLocalResolutionSurvivesNextSync() async throws {
        try await runMerge(localChanged: true, remoteDeleted: false, resolveKeepingRemote: false)
    }
    @MainActor func testKeepRemoteResolutionAcceptsCloudVersion() async throws {
        try await runMerge(localChanged: true, remoteDeleted: false, resolveKeepingRemote: true)
    }

    @MainActor func testKeepLocalCustomerAndTripHandleRemoteClockAhead() throws {
        let oldScope = DataOwnership.activeScope
        let email = "isolated-resolution-regression@example.invalid"
        DataOwnership.activateCloud(email: email)
        defer { DataOwnership.activateLocal(scope: oldScope) }
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let baseline = Date(timeIntervalSince1970: 1700000000)
        let remoteDate = Date.now.addingTimeInterval(3600)
        let customer = Custumer(name: "Keep local customer", email: "", csource: "", type: 1,
                               createdAt: baseline, updateAt: baseline.addingTimeInterval(60), syncBaseUpdatedAt: baseline)
        let trip = TripBookingRecord(form: NewTripFormModel())
        trip.memo = "Keep local memo"
        trip.createdAt = baseline
        trip.updatedAt = baseline.addingTimeInterval(60)
        trip.syncBaseUpdatedAt = baseline
        context.insert(customer)
        context.insert(trip)
        let customerConflict = CloudSyncConflict(tableName: "customers", recordID: customer.uuid,
            ownerScope: DataOwnership.activeScope, localUpdatedAt: customer.updateAt, remoteUpdatedAt: remoteDate, remotePayloadJSON: "{}")
        let tripConflict = CloudSyncConflict(tableName: "trips", recordID: trip.id.uuidString.lowercased(),
            ownerScope: DataOwnership.activeScope, localUpdatedAt: trip.updatedAt!, remoteUpdatedAt: remoteDate, remotePayloadJSON: "{}")
        context.insert(customerConflict)
        context.insert(tripConflict)
        try context.save()
        try SupabaseDataSync.resolveConflict(customerConflict, keepRemote: false, context: context)
        try SupabaseDataSync.resolveConflict(tripConflict, keepRemote: false, context: context)
        XCTAssertEqual(customer.name, "Keep local customer")
        XCTAssertEqual(trip.memo, "Keep local memo")
        XCTAssertEqual(customer.syncBaseUpdatedAt, remoteDate)
        XCTAssertEqual(trip.syncBaseUpdatedAt, remoteDate)
        XCTAssertGreaterThan(customer.updateAt, remoteDate)
        XCTAssertGreaterThan(try XCTUnwrap(trip.updatedAt), remoteDate)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CloudSyncConflict>()).isEmpty)
    }

}


final class CloudRepositoryRegressionTests: XCTestCase {
    @MainActor
    func runPatch(returnedRows: String, wrongAccountBefore: Bool = false, switchAccountAfter: Bool = false, status: Int = 200, expectedFlightContext: [String: String]? = nil) async throws {
        let owner = "00000000-0000-0000-0000-000000000001"
        let other = "00000000-0000-0000-0000-000000000009"
        let tripID = "00000000-0000-0000-0000-000000000002"
        let email = "isolated-cloud-repository@example.invalid"
        let account = CloudOnlineRepository.Account(id: owner, email: email)
        var userRequests = 0
        var patchRequests = 0
        SyncFixtureProtocol.handle = { fixture in
            if fixture.request.url!.path == "/auth/v1/user" {
                userRequests += 1
                let id = wrongAccountBefore || (switchAccountAfter && userRequests > 1) ? other : owner
                fixture.respond("{\"id\":\"\(id)\",\"email\":\"\(email)\"}")
            } else {
                patchRequests += 1
                XCTAssertEqual(fixture.request.httpMethod, "PATCH")
                XCTAssertEqual(fixture.request.url!.path, "/rest/v1/trips")
                let query = URLComponents(url: fixture.request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                XCTAssertEqual(query.first(where: { $0.name == "owner_id" })?.value, "eq.\(owner)")
                XCTAssertEqual(query.first(where: { $0.name == "id" })?.value, "eq.\(tripID)")
                XCTAssertEqual(query.first(where: { $0.name == "deleted_at" })?.value, "is.null")
                if expectedFlightContext != nil {
                    let filters = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
                    XCTAssertEqual(filters["flight_info"], #"eq."UA1743""#)
                    XCTAssertEqual(filters["flight_date"], #"eq."2026-10-24T00:00:00Z""#)
                    XCTAssertEqual(filters["service_type"], #"eq."接机""#)
                    XCTAssertEqual(filters["location_start"], #"eq."LAX Terminal 7, \"Arrivals\"\\North""#)
                    XCTAssertEqual(filters["location_end"], #"eq."Fixture destination""#)
                    XCTAssertTrue(fixture.request.url!.absoluteString.contains("%22"))
                }
                var body = fixture.request.httpBody ?? Data()
                if body.isEmpty, let stream = fixture.request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        body.append(contentsOf: buffer.prefix(count))
                    }
                }
                let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                XCTAssertEqual(Set(json?.keys.map { $0 } ?? []), ["is_completed", "is_cancelled"], "A completion patch must not resend stale fare, customer or flight fields")
                XCTAssertEqual(json?["is_completed"] as? Bool, true)
                fixture.respond(returnedRows, status: status)
            }
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer { SyncFixtureProtocol.handle = nil; URLProtocol.unregisterClass(SyncFixtureProtocol.self) }
        let shouldFail = wrongAccountBefore || switchAccountAfter || returnedRows == "[]" || status != 200
        do {
            try await CloudOnlineRepository.updateTripFields(id: tripID,
                fields: ["is_completed": true, "is_cancelled": false], expectedFlightContext: expectedFlightContext, account: account, accessToken: "fixture-only")
            XCTAssertFalse(shouldFail, "Repository must reject failed or unverified mutations")
        } catch {
            XCTAssertTrue(shouldFail, "Unexpected error: \(error)")
            if wrongAccountBefore || switchAccountAfter {
                XCTAssertEqual(error.localizedDescription, CloudOnlineRepository.RepositoryError.accountChanged.localizedDescription)
            }
        }
        XCTAssertEqual(patchRequests, wrongAccountBefore ? 0 : 1)
    }
    private var expectedFlightFixture: [String: String] {
        ["flight_info": "UA1743", "flight_date": "2026-10-24T00:00:00Z", "service_type": "接机",
         "location_start": #"LAX Terminal 7, "Arrivals"\North"#, "location_end": "Fixture destination"]
    }
    @MainActor func testConditionalFlightWriteIncludesOriginalContextAndEscapesAddresses() async throws {
        try await runPatch(returnedRows: "[{\"id\":\"00000000-0000-0000-0000-000000000002\"}]", expectedFlightContext: expectedFlightFixture)
    }
    @MainActor func testConditionalFlightWriteCannotReportSuccessWhenNoRowMatches() async throws {
        try await runPatch(returnedRows: "[]", expectedFlightContext: expectedFlightFixture)
    }
    @MainActor func testCompletionWritesOnlyStatusFields() async throws {
        try await runPatch(returnedRows: "[{\"id\":\"00000000-0000-0000-0000-000000000002\"}]")
    }
    @MainActor func testEmptyMutationResponseDoesNotReportSuccess() async throws {
        try await runPatch(returnedRows: "[]")
    }
    @MainActor func testWrongAccountCannotStartPatch() async throws {
        try await runPatch(returnedRows: "[]", wrongAccountBefore: true)
    }
    @MainActor func testAccountSwitchAfterPatchDoesNotReportSuccess() async throws {
        try await runPatch(returnedRows: "[{\"id\":\"00000000-0000-0000-0000-000000000002\"}]", switchAccountAfter: true)
    }
    @MainActor func testServerFailureDoesNotReportSuccess() async throws {
        try await runPatch(returnedRows: "{\"message\":\"Fixture server unavailable\"}", status: 503)
    }
}

final class CloudDirectoryRegressionTests: XCTestCase {
    @MainActor
    func runReloadScenario(_ scenario: String) async throws {
        let owner = "00000000-0000-0000-0000-000000000001"
        let email = "isolated-cloud-directory@example.invalid"
        let oldScope = DataOwnership.activeScope
        let auth = AuthViewModel()
        var heldRequest: SyncFixtureProtocol?
        var tripRequests = 0
        var mutationRequests = 0
        let firstHeld = expectation(description: "First trip request is suspended")
        if scenario != "late" && scenario != "clear" {
            firstHeld.fulfill()
            await fulfillment(of: [firstHeld], timeout: 1)
        }
        func tripJSON(_ name: String) -> String {
            let row: [String: Any] = [
                "id": "00000000-0000-0000-0000-000000000002", "service_type": "接机", "order_source": "普通客户",
                "travel_agency_code": "", "travel_agency_name": "", "customer_name": name,
                "customer_contact": "", "customer_count": "1", "customer_stuff": "0",
                "appointment_date": "2026-10-24T00:00:00Z", "appointment_time": "2026-10-24T18:10:00Z",
                "location_start": "LAX", "location_end": "Fixture destination", "flight_info": "UA1743",
                "flight_date": "2026-10-24T00:00:00Z", "memo": "", "price": 0, "tip": 0,
                "is_paid": scenario == "remote-paid", "is_completed": scenario == "remote-completed", "is_cancelled": scenario == "remote-cancelled",
                "reminder_enabled": false, "has_second_reminder": false, "currency_code": "USD",
                "created_at": "2026-10-24T00:00:00Z"
            ]
            return String(decoding: try! JSONSerialization.data(withJSONObject: [row]), as: UTF8.self)
        }
        let oldRows = tripJSON("Old response")
        let newRows = tripJSON("Latest response")
        SyncFixtureProtocol.handle = { fixture in
            let path = fixture.request.url!.path
            if path == "/auth/v1/token" {
                fixture.respond("{\"access_token\":\"fixture-only\",\"refresh_token\":\"fixture-refresh\",\"expires_in\":3600,\"user\":{\"email\":\"\(email)\"}}")
            } else if path == "/auth/v1/user" {
                fixture.respond("{\"id\":\"\(owner)\",\"email\":\"\(email)\"}")
            } else if path == "/rest/v1/rpc/delete_online_trip" {
                fixture.respond(scenario == "mutation-delete-failure" ? "{\"message\":\"Fixture delete failed\"}" : "null",
                                status: scenario == "mutation-delete-failure" ? 503 : 200)
            } else if path == "/rest/v1/trips" && fixture.request.httpMethod == "PATCH" {
                mutationRequests += 1
                fixture.respond(scenario == "mutation-patch-failure" ? "{\"message\":\"Fixture patch failed\"}" : "[{\"id\":\"00000000-0000-0000-0000-000000000002\"}]",
                                status: scenario == "mutation-patch-failure" ? 503 : 200)
            } else if path == "/rest/v1/trips" {
                tripRequests += 1
                if scenario.hasPrefix("remote-") { fixture.respond(newRows) }
                else if scenario == "failure" || scenario.hasPrefix("mutation") {
                    if tripRequests == 1 { fixture.respond(newRows) }
                    else if scenario == "mutation-stale-flight" { fixture.respond(newRows.replacingOccurrences(of: "UA1743", with: "UA9999")) }
                    else { fixture.respond("{\"message\":\"Fixture refresh failed\"}", status: 503) }
                } else if tripRequests == 1 {
                    heldRequest = fixture
                    firstHeld.fulfill()
                } else { fixture.respond(newRows) }
            } else if path == "/rest/v1/user_settings" {
                fixture.respond("[{\"currency_code\":\"USD\"}]")
            } else { fixture.respond("[]") }
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer {
            auth.clearIsolatedTestSession()
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        let loginError = await auth.loginToCloud(email: email, password: "fixture-only-not-a-real-credential")
        XCTAssertNil(loginError)
        guard loginError == nil else { return }
        let directory = CloudTripDirectoryModel()
        if scenario.hasPrefix("remote-") {
            let expected = scenario == "remote-paid" ? [] : [try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))]
            TripReminderScheduler.cancelledTripIDs = []
            await directory.reloadTrips(using: auth)
            XCTAssertEqual(TripReminderScheduler.cancelledTripIDs, expected)
            TripReminderScheduler.cancelledTripIDs = []
            await directory.reload(using: auth)
            XCTAssertEqual(TripReminderScheduler.cancelledTripIDs, expected)
            XCTAssertEqual(directory.trips.count, 1)
        } else if scenario.hasPrefix("mutation") {
            await directory.reloadTrips(using: auth)
            let trip = try XCTUnwrap(directory.trips.first)
            if scenario == "mutation-stale-flight" { await directory.reloadTrips(using: auth) }
            let candidate = VariFlightLookupResult(airlineName: "Fixture", departureAirport: "IAH", arrivalAirport: "LAX", departureTerminal: nil, arrivalTerminal: "7", departureTime: "16:30", estimatedArrivalTime: "18:07", baggageCarousel: nil)
            let snapshot = SavedFlightSelection(flightNumber: trip.flightInfo, flightDate: Date(timeIntervalSince1970: 1700000000), selected: candidate)
            TripReminderScheduler.cancelledTripIDs = []
            let result: Bool
            if scenario.contains("delete") {
                result = await directory.delete(id: trip.id, using: auth)
            } else if scenario == "mutation-flight" || scenario == "mutation-stale-flight" {
                result = await directory.updateStatus(for: trip, flightSelectionSnapshot: snapshot, using: auth)
            } else if scenario == "mutation-paid" {
                result = await directory.updateStatus(for: trip, isPaid: true, using: auth)
            } else {
                result = await directory.updateStatus(for: trip, isCompleted: true, using: auth)
            }
            let rejected = scenario.hasSuffix("failure") || scenario == "mutation-stale-flight"
            XCTAssertEqual(result, !rejected)
            XCTAssertEqual(TripReminderScheduler.cancelledTripIDs, scenario == "mutation-completed" ? [try XCTUnwrap(UUID(uuidString: trip.id))] : [])
            if scenario == "mutation-delete" {
                XCTAssertTrue(directory.trips.isEmpty, "A confirmed deletion must stay removed when subsequent refresh fails")
            } else {
                let cached = try XCTUnwrap(directory.trips.first)
                XCTAssertEqual(cached.isCompleted, scenario == "mutation-completed")
                XCTAssertEqual(cached.isPaid, scenario == "mutation-paid")
                XCTAssertEqual(cached.flightSelectionSnapshot, scenario == "mutation-flight" ? snapshot : nil)
                if scenario == "mutation-flight" {
                    XCTAssertEqual(cached.flightDepartureTime, candidate.departureTime)
                    XCTAssertEqual(cached.flightArrivalTerminal, "7")
                }
                XCTAssertEqual(cached.customerName, trip.customerName)
                XCTAssertEqual(cached.price, trip.price)
                XCTAssertEqual(cached.flightInfo, scenario == "mutation-stale-flight" ? "UA9999" : trip.flightInfo)
                if scenario == "mutation-stale-flight" { XCTAssertEqual(mutationRequests, 0) }
            }
            XCTAssertNotNil(directory.errorMessage, "Refresh or mutation failure must remain visible")
        } else if scenario == "failure" {
            await directory.reloadTrips(using: auth)
            XCTAssertEqual(directory.trips.first?.customerName, "Latest response")
            await directory.reloadTrips(using: auth)
            XCTAssertEqual(directory.trips.first?.customerName, "Latest response", "A refresh error must not erase already loaded trips")
            XCTAssertNotNil(directory.errorMessage)
        } else {
            let earlierReload = Task { @MainActor in await directory.reloadTrips(using: auth) }
            await fulfillment(of: [firstHeld], timeout: 5)
            if scenario == "clear" { directory.clearForAccountChange() }
            else { await directory.reloadTrips(using: auth) }
            try XCTUnwrap(heldRequest).respond(oldRows)
            await earlierReload.value
            if scenario == "clear" {
                XCTAssertTrue(directory.trips.isEmpty, "A late response must not repopulate data after account clearing")
            } else {
                XCTAssertEqual(directory.trips.first?.customerName, "Latest response", "An older request must not overwrite the newer reload")
            }
        }
        XCTAssertFalse(directory.isLoading)
    }
    @MainActor func testRemoteCompletionCancelsRemindersOnBothReloadPaths() async throws { try await runReloadScenario("remote-completed") }
    @MainActor func testRemoteCancellationCancelsRemindersOnBothReloadPaths() async throws { try await runReloadScenario("remote-cancelled") }
    @MainActor func testRemotePaymentDoesNotCancelPendingTripReminders() async throws { try await runReloadScenario("remote-paid") }
    @MainActor func testLateReloadCannotOverwriteNewerResponse() async throws { try await runReloadScenario("late") }
    @MainActor func testLateResponseCannotRepopulateClearedAccount() async throws { try await runReloadScenario("clear") }
    @MainActor func testRefreshFailureKeepsPreviouslyLoadedTrips() async throws { try await runReloadScenario("failure") }
    @MainActor func testStaleFlightCannotOverwriteKnownChangedTrip() async throws { try await runReloadScenario("mutation-stale-flight") }
    @MainActor func testConfirmedCompletionSurvivesRefreshFailure() async throws { try await runReloadScenario("mutation-completed") }
    @MainActor func testConfirmedPaymentSurvivesRefreshFailure() async throws { try await runReloadScenario("mutation-paid") }
    @MainActor func testConfirmedFlightSurvivesRefreshFailure() async throws { try await runReloadScenario("mutation-flight") }
    @MainActor func testConfirmedDeletionSurvivesRefreshFailure() async throws { try await runReloadScenario("mutation-delete") }
    @MainActor func testRejectedStatusDoesNotChangeCache() async throws { try await runReloadScenario("mutation-patch-failure") }
    @MainActor func testRejectedDeletionDoesNotRemoveCache() async throws { try await runReloadScenario("mutation-delete-failure") }
}

final class SyncBackgroundExecutionTests: XCTestCase {
    @MainActor
    func testSuccessReleasesBackgroundTimeOnce() async throws {
        var ended: [UIBackgroundTaskIdentifier] = []
        let id = UIBackgroundTaskIdentifier(rawValue: 42)
        let result = try await SyncBackgroundExecution.run(begin: { _ in id }, end: { ended.append($0) }) { 7 }
        XCTAssertEqual(result, 7)
        XCTAssertEqual(ended, [id])
    }

    @MainActor
    func testFailureReleasesBackgroundTimeOnce() async {
        var ended = 0
        do {
            let _: Int = try await SyncBackgroundExecution.run(
                begin: { _ in UIBackgroundTaskIdentifier(rawValue: 42) }, end: { _ in ended += 1 }
            ) { throw URLError(.notConnectedToInternet) }
            XCTFail("A failed request must not become success")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(ended, 1)
    }

    @MainActor
    func testExpirationCancelsWorkAndEndsOnlyOnce() async {
        var expiration: (@MainActor @Sendable () -> Void)?
        var ended = 0
        let started = expectation(description: "Network work started")
        let task = Task { @MainActor in
            try await SyncBackgroundExecution.run(
                begin: { expiration = $0; return UIBackgroundTaskIdentifier(rawValue: 42) },
                end: { _ in ended += 1 }
            ) {
                started.fulfill()
                try await Task.sleep(for: .seconds(30))
                return 7
            }
        }
        await fulfillment(of: [started], timeout: 2)
        expiration?()
        do { _ = try await task.value; XCTFail("Expired work must be cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(ended, 1)
    }

    @MainActor
    func testDeniedBackgroundTimeDoesNotEndInvalidIdentifier() async throws {
        var ended = 0
        let result = try await SyncBackgroundExecution.run(begin: { _ in .invalid }, end: { _ in ended += 1 }) { 7 }
        XCTAssertEqual(result, 7)
        XCTAssertEqual(ended, 0)
    }
}

final class SyncBackgroundCancellationTests: XCTestCase {
    @MainActor
    func testParentCancellationStopsWorkerAndReleasesTime() async {
        let started = expectation(description: "Worker started")
        var ended = 0
        let parent = Task { @MainActor in
            try await SyncBackgroundExecution.run(
                begin: { _ in UIBackgroundTaskIdentifier(rawValue: 43) }, end: { _ in ended += 1 }
            ) {
                started.fulfill()
                try await Task.sleep(for: .seconds(30))
                return 7
            }
        }
        await fulfillment(of: [started], timeout: 2)
        parent.cancel()
        do { _ = try await parent.value; XCTFail("Parent cancellation must reach its worker") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(ended, 1)
    }

    @MainActor
    func testExpiredOperationCannotReportSuccessWhenItIgnoresCancellation() async {
        let started = expectation(description: "Worker started")
        var expiration: (@MainActor @Sendable () -> Void)?
        var ended = 0
        let parent = Task { @MainActor in
            try await SyncBackgroundExecution.run(
                begin: { expiration = $0; return UIBackgroundTaskIdentifier(rawValue: 44) },
                end: { _ in ended += 1 }
            ) {
                started.fulfill()
                try? await Task.sleep(for: .seconds(30))
                return 7
            }
        }
        await fulfillment(of: [started], timeout: 2)
        expiration?()
        do { _ = try await parent.value; XCTFail("A cancelled operation must not report success") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(ended, 1)
    }
}

final class CloudPurchaseEntryAccessTests: XCTestCase {
    @MainActor private func check(_ scenario: String, allowed: Bool) async throws {
        let oldScope = DataOwnership.activeScope
        let email = "purchase-entry-\(UUID().uuidString.lowercased())@example.invalid"
        let auth = AuthViewModel()
        var registered = 0
        SyncFixtureProtocol.handle = { fixture in
            switch fixture.request.url!.path {
            case "/auth/v1/token":
                fixture.respond("{\"access_token\":\"fixture-access\",\"refresh_token\":\"fixture-refresh\",\"user\":{\"email\":\"\(email)\"}}")
            case "/rest/v1/account_entitlements":
                if scenario == "unknown" { fixture.respond("[]") }
                else if scenario == "unavailable" { fixture.respond("{}", status: 503) }
                else if scenario == "legacy" { fixture.respond("{}", status: 404) }
                else {
                    let status = scenario == "revoked" ? "revoked" : "active"
                    let expiry = scenario == "expired" ? "\"2000-01-01T00:00:00Z\"" : "null"
                    fixture.respond("[{\"edition\":\"cloud\",\"status\":\"\(status)\",\"expires_at\":\(expiry),\"max_devices\":4}]")
                }
            case "/rest/v1/rpc/register_account_device":
                registered += 1
                if scenario == "full" { fixture.respond("{\"message\":\"ACCOUNT_DEVICE_LIMIT_REACHED\"}", status: 403) }
                else { fixture.respond("{\"active_devices\":1,\"max_devices\":4}") }
            default: fixture.respond("{}")
            }
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer {
            auth.clearIsolatedTestSession(); DataOwnership.activateLocal(scope: oldScope)
            UserDefaults.standard.removeObject(forKey: "account.entitlement.cache.v1.\(email)")
            SyncFixtureProtocol.handle = nil; URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        XCTAssertFalse(auth.canManageCloudPurchases)
        let login = await auth.loginToCloud(email: email, password: "fixture-only")
        XCTAssertNil(login)
        XCTAssertFalse(auth.canManageCloudPurchases, "Unverified startup state must not offer payment")
        await auth.loadServerEntitlementIfNeeded()
        XCTAssertEqual(auth.canManageCloudPurchases, allowed)
        if scenario == "expired" {
            XCTAssertFalse(auth.canUseCurrentCloudEdition)
            XCTAssertTrue(auth.canReadExpiredArchive)
            XCTAssertEqual(registered, 0, "Renewal entry must not require active cloud access")
        }
    }
    @MainActor func testExpiredAccountCanReachRenewalWithoutOpeningBusinessWrites() async throws { try await check("expired", allowed: true) }
    @MainActor func testRevokedAccountCannotReachPayment() async throws { try await check("revoked", allowed: false) }
    @MainActor func testUnknownGrantCannotReachPayment() async throws { try await check("unknown", allowed: false) }
    @MainActor func testUnavailableAuthorizationCannotReachPayment() async throws { try await check("unavailable", allowed: false) }
    @MainActor func testLegacyFallbackDoesNotAuthorizeNewPayment() async throws { try await check("legacy", allowed: false) }
    @MainActor func testFullDeviceAllowanceDoesNotOfferAnotherCharge() async throws { try await check("full", allowed: false) }
    @MainActor func testVerifiedActiveAccountCanManagePurchases() async throws { try await check("active", allowed: true) }
}

final class AuthRefreshRecoveryTests: XCTestCase {
    @MainActor func testLogoutReleasesDeviceBeforeRevokingOnlyCurrentSession() async throws {
        let oldScope = DataOwnership.activeScope
        let auth = AuthViewModel()
        let signedOut = expectation(description: "Current session signed out")
        var paths: [String] = []
        var otherSessionActive = true
        SyncFixtureProtocol.handle = { fixture in
            let path = fixture.request.url!.path
            if path == "/auth/v1/token" {
                fixture.respond("{\"access_token\":\"fixture-access\",\"refresh_token\":\"fixture-refresh\",\"user\":{\"email\":\"logout-scope@example.invalid\"}}")
            } else if path == "/rest/v1/rpc/release_account_device" {
                paths.append(path)
                fixture.respond("{}")
            } else if path == "/auth/v1/logout" {
                paths.append(path)
                let scope = URLComponents(url: fixture.request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "scope" }?.value
                otherSessionActive = scope == "local"
                fixture.respond("{}")
                signedOut.fulfill()
            } else { fixture.respond("[]") }
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer {
            auth.clearIsolatedTestSession(); DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil; URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        let error = await auth.loginToCloud(email: "logout-scope@example.invalid", password: "fixture-only")
        XCTAssertNil(error)
        auth.logout()
        XCTAssertFalse(auth.isLoggedIn)
        await fulfillment(of: [signedOut], timeout: 5)
        XCTAssertEqual(paths, ["/rest/v1/rpc/release_account_device", "/auth/v1/logout"])
        XCTAssertTrue(otherSessionActive, "Ordinary device logout must not revoke another device's session")
    }

    @MainActor private func delayedRefreshAfterLogout(rejected: Bool) async throws {
        let oldScope = DataOwnership.activeScope
        let auth = AuthViewModel()
        let email = "isolated-delayed-refresh@example.invalid"
        var held: SyncFixtureProtocol?
        var requests = 0
        let waiting = expectation(description: "Refresh held until logout")
        let logoutCompleted = expectation(description: "Background logout completed before fixture teardown")
        SyncFixtureProtocol.handle = { fixture in
            if fixture.request.url?.path == "/auth/v1/token" {
                requests += 1
                if requests == 1 { fixture.respond("{\"access_token\":\"fixture-access\",\"refresh_token\":\"fixture-refresh\",\"user\":{\"email\":\"\(email)\"}}") }
                else { held = fixture; waiting.fulfill() }
            } else if fixture.request.url?.path == "/auth/v1/logout" {
                fixture.respond("{}")
                logoutCompleted.fulfill()
            } else { fixture.respond("[]") }
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer { auth.clearIsolatedTestSession(); DataOwnership.activateLocal(scope: oldScope); SyncFixtureProtocol.handle = nil; URLProtocol.unregisterClass(SyncFixtureProtocol.self) }
        let error = await auth.loginToCloud(email: email, password: "fixture-only")
        XCTAssertNil(error)
        let task = Task { @MainActor in await auth.refreshCloudAccessToken() }
        await fulfillment(of: [waiting], timeout: 5)
        auth.logout()
        if rejected { try XCTUnwrap(held).respond("{\"message\":\"expired\"}", status: 401) }
        else { try XCTUnwrap(held).respond("{\"access_token\":\"stale-access\",\"refresh_token\":\"stale-refresh\",\"user\":{\"email\":\"\(email)\"}}") }
        let value = await task.value
        XCTAssertNil(value); XCTAssertNil(auth.cloudAccessToken); XCTAssertFalse(auth.isLoggedIn); XCTAssertFalse(auth.requiresCloudReauthentication)
        await fulfillment(of: [logoutCompleted], timeout: 5)
    }
    @MainActor func testLateRefreshSuccessCannotRestoreLoggedOutSession() async throws { try await delayedRefreshAfterLogout(rejected: false) }
    @MainActor func testLateRefreshRejectionDoesNotMarkLoggedOutSessionExpired() async throws { try await delayedRefreshAfterLogout(rejected: true) }

    @MainActor
    func runRefreshFailure(_ code: URLError.Code?, unauthorized: Bool = false) async throws {
        let oldScope = DataOwnership.activeScope
        let auth = AuthViewModel()
        let email = "isolated-refresh-recovery@example.invalid"
        var tokenRequests = 0
        SyncFixtureProtocol.handle = { fixture in
            guard fixture.request.url?.path == "/auth/v1/token" else { fixture.respond("[]"); return }
            tokenRequests += 1
            if tokenRequests == 1 {
                fixture.respond("{\"access_token\":\"fixture-access\",\"refresh_token\":\"fixture-refresh\",\"expires_in\":3600,\"user\":{\"email\":\"\(email)\"}}")
            } else if unauthorized {
                fixture.respond("{\"message\":\"Fixture refresh token expired\"}", status: 401)
            } else {
                fixture.client?.urlProtocol(fixture, didFailWithError: URLError(code!))
            }
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer {
            auth.clearIsolatedTestSession()
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        let loginError = await auth.loginToCloud(email: email, password: "fixture-only")
        XCTAssertNil(loginError)
        guard loginError == nil else { return }
        let refreshed = await auth.refreshCloudAccessToken()
        XCTAssertNil(refreshed)
        XCTAssertEqual(tokenRequests, 2)
        XCTAssertEqual(auth.requiresCloudReauthentication, unauthorized,
                       "Only a confirmed authentication rejection should require signing in again")
        XCTAssertTrue(auth.isLoggedIn)
        XCTAssertEqual(auth.cloudAccessToken, "fixture-access", "A network interruption must not erase the existing credential")
    }
    @MainActor func testCancelledRefreshDoesNotRequireLoginAgain() async throws { try await runRefreshFailure(.cancelled) }
    @MainActor func testOfflineRefreshDoesNotRequireLoginAgain() async throws { try await runRefreshFailure(.notConnectedToInternet) }
    @MainActor func testRejectedRefreshRequiresReauthentication() async throws { try await runRefreshFailure(nil, unauthorized: true) }
}

final class FlightEditorRaceTests: XCTestCase {
    @MainActor
    func runRace(_ harness: any FlightRaceHarness, mode: String) async throws {
        let firstStarted = expectation(description: "Old flight request started")
        let secondStarted = expectation(description: "New flight request started")
        var oldResponse: CheckedContinuation<[VariFlightLookupResult], Error>?
        var newResponse: CheckedContinuation<[VariFlightLookupResult], Error>?
        let candidate = VariFlightLookupResult(airlineName: "Fixture", departureAirport: "SFO", arrivalAirport: "LAX", departureTerminal: nil, arrivalTerminal: "7", departureTime: "16:30", estimatedArrivalTime: "18:07", baggageCarousel: nil)
        let oldCandidate = VariFlightLookupResult(airlineName: "Old fixture", departureAirport: "IAH", arrivalAirport: "LAX", departureTerminal: nil, arrivalTerminal: "8", departureTime: "14:00", estimatedArrivalTime: "16:00", baggageCarousel: nil)
        FlightRaceClient.handler = { number in
            try await withCheckedThrowingContinuation { continuation in
                if number == "UA1" { oldResponse = continuation; firstStarted.fulfill() }
                else { newResponse = continuation; secondStarted.fulfill() }
            }
        }
        defer { FlightRaceClient.handler = nil }
        harness.lookupFlight()
        let oldTask = try XCTUnwrap(harness.flightLookupTask)
        await fulfillment(of: [firstStarted], timeout: 2)
        if mode == "clear" {
            secondStarted.fulfill()
            await fulfillment(of: [secondStarted], timeout: 1)
            harness.invalidateFlightSelection()
            XCTAssertFalse(harness.isLookingUpFlight)
            oldResponse?.resume(returning: [oldCandidate])
            await oldTask.value
            XCTAssertNil(harness.flightLookupResult)
            XCTAssertNil(harness.savedFlightNumber)
            XCTAssertTrue(harness.flightCandidates.isEmpty)
            return
        }
        harness.changeNumber("UA2")
        harness.lookupFlight()
        let newTask = try XCTUnwrap(harness.flightLookupTask)
        await fulfillment(of: [secondStarted], timeout: 2)
        if mode == "error" {
            oldResponse?.resume(throwing: URLError(.timedOut))
            await oldTask.value
            XCTAssertTrue(harness.isLookingUpFlight, "An old failure must not stop a newer request's loading state")
            XCTAssertNil(harness.flightLookupError)
            newResponse?.resume(returning: [candidate])
            await newTask.value
        } else {
            newResponse?.resume(returning: [candidate])
            await newTask.value
            oldResponse?.resume(returning: [oldCandidate])
            await oldTask.value
        }
        XCTAssertEqual(harness.savedFlightNumber, "UA2", "The old response must never be saved under the new flight number")
        XCTAssertEqual(harness.flightLookupResult, candidate)
        XCTAssertNil(harness.flightLookupError)
        XCTAssertFalse(harness.isLookingUpFlight)
    }
    @MainActor func testCloudOldSuccessCannotReplaceNewFlight() async throws { try await runRace(CloudFlightRaceHarness(), mode: "success") }
    @MainActor func testLocalOldSuccessCannotReplaceNewFlight() async throws { try await runRace(LocalFlightRaceHarness(), mode: "success") }
    @MainActor func testCloudOldFailureCannotStopNewQuery() async throws { try await runRace(CloudFlightRaceHarness(), mode: "error") }
    @MainActor func testLocalOldFailureCannotStopNewQuery() async throws { try await runRace(LocalFlightRaceHarness(), mode: "error") }
    @MainActor func testCloudClearingPendingQueryDropsItsResponse() async throws { try await runRace(CloudFlightRaceHarness(), mode: "clear") }
    @MainActor func testLocalClearingPendingQueryDropsItsResponse() async throws { try await runRace(LocalFlightRaceHarness(), mode: "clear") }
}

final class FlightRefreshSaveStateTests: XCTestCase {
    @MainActor
    func runSave(_ harness: any FlightReadOnlyHarness, saved: Bool, superseded: Bool = false) async throws {
        let saving = expectation(description: "Snapshot save started")
        let candidate = VariFlightLookupResult(airlineName: "Fixture", departureAirport: "SFO", arrivalAirport: "LAX", departureTerminal: nil, arrivalTerminal: "7", departureTime: "16:30", estimatedArrivalTime: "18:07", baggageCarousel: nil)
        FlightRaceClient.handler = { _ in [candidate] }
        defer { FlightRaceClient.handler = nil }
        let previous = VariFlightLookupResult(airlineName: "Saved", departureAirport: "IAH", arrivalAirport: "LAX", departureTerminal: "C", arrivalTerminal: "7", departureTime: "15:00", estimatedArrivalTime: "17:00", baggageCarousel: nil)
        harness.flightLookupResult = previous
        harness.directory.started = { saving.fulfill() }
        harness.lookupFlight(forceRefresh: true)
        await harness.lookupTask?.value
        await fulfillment(of: [saving], timeout: 2)
        XCTAssertEqual(harness.flightLookupResult, previous, "Unconfirmed selection must not replace the saved flight")
        XCTAssertTrue(harness.isLookingUpFlight, "Auto-selection must stay busy while snapshot saving is suspended")
        if superseded {
            harness.savedFlightDisplayContext += 1
            harness.flightLookupResult = previous
        }
        harness.directory.finish(saved: saved)
        await harness.selectionTask?.value
        XCTAssertFalse(harness.isLookingUpFlight)
        XCTAssertEqual(harness.flightLookupError, (saved || superseded) ? nil : "Fixture save failed")
        XCTAssertEqual(harness.flightLookupResult, (saved && !superseded) ? candidate : previous)
    }
    @MainActor
    func runChoice(_ harness: any FlightReadOnlyHarness) async {
        let candidate = VariFlightLookupResult(airlineName: "Fixture", departureAirport: "SFO", arrivalAirport: "LAX", departureTerminal: nil, arrivalTerminal: "7", departureTime: "16:30", estimatedArrivalTime: "18:07", baggageCarousel: nil)
        FlightRaceClient.handler = { _ in [candidate, candidate] }
        defer { FlightRaceClient.handler = nil }
        harness.lookupFlight(forceRefresh: true)
        await harness.lookupTask?.value
        XCTAssertFalse(harness.isLookingUpFlight, "Waiting for the user's choice must not keep a network spinner running")
        XCTAssertTrue(harness.isChoosingFlight)
        XCTAssertNil(harness.selectionTask)
    }
    @MainActor func testCardBusyUntilSaveCompletes() async throws { try await runSave(FlightManagementCardHarness(), saved: true) }
    @MainActor func testDetailBusyUntilSaveCompletes() async throws { try await runSave(FlightDetailViewHarness(), saved: true) }
    @MainActor func testCardSaveFailureStopsBusyAndShowsError() async throws { try await runSave(FlightManagementCardHarness(), saved: false) }
    @MainActor func testDetailSaveFailureStopsBusyAndShowsError() async throws { try await runSave(FlightDetailViewHarness(), saved: false) }
    @MainActor func testCardSupersededSaveSuccessPreservesNewSnapshot() async throws { try await runSave(FlightManagementCardHarness(), saved: true, superseded: true) }
    @MainActor func testCardSupersededSaveFailurePreservesNewSnapshot() async throws { try await runSave(FlightManagementCardHarness(), saved: false, superseded: true) }
    @MainActor func testDetailSupersededSaveSuccessPreservesNewSnapshot() async throws { try await runSave(FlightDetailViewHarness(), saved: true, superseded: true) }
    @MainActor func testDetailSupersededSaveFailurePreservesNewSnapshot() async throws { try await runSave(FlightDetailViewHarness(), saved: false, superseded: true) }
    @MainActor func testCardChoiceStopsQuerySpinner() async { await runChoice(FlightManagementCardHarness()) }
    @MainActor func testDetailChoiceStopsQuerySpinner() async { await runChoice(FlightDetailViewHarness()) }
}

final class SettlementValidationTests: XCTestCase {
    func testZeroSettlementRemainsAllowed() {
        XCTAssertNil(SettlementValidation.validate(fare: 0, tip: 0, expenses: []))
    }
    func testAdditionsAndDeductionsRemainAllowed() {
        let expenses = [SettlementValidation.Expense(title: "Parking", amount: 10, isAddition: true),
                        SettlementValidation.Expense(title: "Cost", amount: 120, isAddition: false)]
        XCTAssertNil(SettlementValidation.validate(fare: 90, tip: 5, expenses: expenses), "A negative net total remains valid when caused by explicit deductions")
    }
    func testNegativeFareOrTipIsRejected() {
        XCTAssertEqual(SettlementValidation.validate(fare: -1, tip: 0, expenses: []), .negativeFare)
        XCTAssertEqual(SettlementValidation.validate(fare: 0, tip: -1, expenses: []), .negativeFare)
    }
    func testMissingAndNonFiniteFareOrTipIsRejected() {
        for value: Double? in [nil, .nan, .infinity, -.infinity] {
            XCTAssertEqual(SettlementValidation.validate(fare: value, tip: 0, expenses: []), .invalidFare)
            XCTAssertEqual(SettlementValidation.validate(fare: 0, tip: value, expenses: []), .invalidFare)
        }
    }
    func testNamedExpenseRequiresPositiveFiniteAmount() {
        for amount: Double? in [nil, 0, -1, .nan, .infinity] {
            XCTAssertEqual(SettlementValidation.validate(fare: 90, tip: 0, expenses: [.init(title: "Cost", amount: amount, isAddition: false)]), .invalidExpense)
        }
    }
    func testOnlyUnnamedZeroExpenseIsIgnored() {
        XCTAssertNil(SettlementValidation.validate(fare: 0, tip: 0, expenses: [.init(title: "  ", amount: 0, isAddition: false)]))
        for amount: Double? in [nil, 10, -1, .nan, .infinity] {
            XCTAssertEqual(SettlementValidation.validate(fare: 90, tip: 0, expenses: [.init(title: "  ", amount: amount, isAddition: false)]), .invalidExpense)
        }
    }
    func testInvalidExpenseTextCannotBecomeAnUnusedZeroRow() {
        for text in ["abc", "12.3.4", "--1"] {
            let amount = SettlementValidation.expenseAmount(from: text)
            XCTAssertNil(amount)
            XCTAssertEqual(SettlementValidation.validate(fare: 90, tip: 0, expenses: [.init(title: "", amount: amount, isAddition: false)]), .invalidExpense)
        }
        XCTAssertEqual(SettlementValidation.expenseAmount(from: "  "), 0)
        XCTAssertEqual(SettlementValidation.expenseAmount(from: " 10.50 "), 10.5)
    }
    func testOverflowIsRejected() {
        XCTAssertEqual(SettlementValidation.validate(fare: .greatestFiniteMagnitude, tip: .greatestFiniteMagnitude, expenses: []), .invalidTotal)
        XCTAssertEqual(SettlementValidation.validate(fare: .greatestFiniteMagnitude, tip: 0, expenses: [.init(title: "Extra", amount: .greatestFiniteMagnitude, isAddition: true)]), .invalidTotal)
    }
}

final class SettlementPersistenceTests: XCTestCase {
    enum FixtureFailure: Error { case diskWrite }

    @MainActor
    func runFailure(alreadyPaid: Bool, originalDate: Date?) throws {
        let booking = TripBookingRecord(form: NewTripFormModel())
        booking.price = 90
        booking.tip = 5
        booking.isCompleted = true
        booking.isPaid = alreadyPaid
        booking.updatedAt = originalDate
        booking.expenseAdjustments = [.init(isAddition: false, title: "Original cost", amount: 10)]
        let originalJSON = booking.expenseAdjustmentsJSON
        booking.memo = "An unrelated pending edit"
        XCTAssertThrowsError(try SettlementValidation.save(booking: booking, fare: 120, tip: 15, expenses: [.init(isAddition: true, title: "Extra", amount: 20)]) {
            XCTAssertEqual(booking.price, 120)
            XCTAssertTrue(booking.isPaid)
            throw FixtureFailure.diskWrite
        }) { XCTAssertTrue($0 is FixtureFailure) }
        XCTAssertEqual(booking.price, 90)
        XCTAssertEqual(booking.tip, 5)
        XCTAssertEqual(booking.expenseAdjustmentsJSON, originalJSON)
        XCTAssertEqual(booking.isPaid, alreadyPaid)
        XCTAssertEqual(booking.updatedAt, originalDate)
        XCTAssertTrue(booking.isCompleted)
        XCTAssertEqual(booking.memo, "An unrelated pending edit")
    }
    @MainActor func testFailedSettlementRestoresUnpaidFinancialFields() throws {
        try runFailure(alreadyPaid: false, originalDate: Date(timeIntervalSince1970: 1700000000))
    }
    @MainActor func testFailedSettlementPreservesPaidStateAndLegacyTimestamp() throws {
        try runFailure(alreadyPaid: true, originalDate: nil)
    }
    @MainActor func testInvalidSettlementNeverMutatesOrCallsPersistence() throws {
        let booking = TripBookingRecord(form: NewTripFormModel())
        booking.price = 90
        let originalDate = booking.updatedAt
        var persisted = false
        XCTAssertThrowsError(try SettlementValidation.save(booking: booking, fare: .infinity, tip: 0, expenses: []) {
            persisted = true
        }) { XCTAssertEqual($0 as? SettlementValidation.Failure, .invalidFare) }
        XCTAssertFalse(persisted)
        XCTAssertEqual(booking.price, 90)
        XCTAssertFalse(booking.isPaid)
        XCTAssertEqual(booking.updatedAt, originalDate)
    }
    @MainActor func testRetryAfterFailurePersistsOnlyConfirmedSettlement() throws {
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let booking = TripBookingRecord(form: NewTripFormModel())
        booking.price = 90
        booking.isCompleted = true
        context.insert(booking)
        try context.save()
        booking.memo = "Preserve unrelated edit"
        XCTAssertThrowsError(try SettlementValidation.save(booking: booking, fare: 999, tip: 99, expenses: []) {
            throw FixtureFailure.diskWrite
        })
        try SettlementValidation.save(booking: booking, fare: 100, tip: 5, expenses: [.init(), .init(isAddition: false, title: "Parking", amount: 10)]) {
            try context.save()
        }
        let readback = ModelContext(container)
        let saved = try XCTUnwrap(readback.fetch(FetchDescriptor<TripBookingRecord>()).first)
        XCTAssertEqual(saved.price, 100)
        XCTAssertEqual(saved.tip, 5)
        XCTAssertTrue(saved.isPaid)
        XCTAssertTrue(saved.isCompleted)
        XCTAssertEqual(saved.memo, "Preserve unrelated edit")
        XCTAssertEqual(saved.expenseAdjustments.count, 1)
        XCTAssertEqual(saved.expenseAdjustments.first?.title, "Parking")
        XCTAssertEqual(saved.expenseAdjustments.first?.amount, 10)
    }
}

final class SettlementAmountInputTests: XCTestCase {
    func testUSAmountAndGrouping() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(SettlementAmountInput.parse("1,234.50", locale: locale), 1234.5)
        XCTAssertEqual(SettlementAmountInput.parse("1234.50", locale: locale), 1234.5)
        XCTAssertEqual(SettlementAmountInput.parse(".50", locale: locale), 0.5)
        XCTAssertEqual(SettlementAmountInput.parse("12.", locale: locale), 12)
    }
    func testDecimalCommaAndGrouping() {
        let locale = Locale(identifier: "de_DE")
        XCTAssertEqual(SettlementAmountInput.parse("1.234,50", locale: locale), 1234.5)
        XCTAssertEqual(SettlementAmountInput.parse("1234,50", locale: locale), 1234.5)
        XCTAssertEqual(SettlementAmountInput.parse(",50", locale: locale), 0.5)
        XCTAssertNil(SettlementAmountInput.parse("1.23", locale: locale), "An invalid grouping must not silently become 123")
    }
    func testFormattedValuesRoundTripAcrossLocales() throws {
        for identifier in ["en_US", "de_DE", "fr_FR", "hi_IN", "ar_EG"] {
            let locale = Locale(identifier: identifier)
            let formatter = NumberFormatter()
            formatter.locale = locale
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            let text = try XCTUnwrap(formatter.string(from: 1234567.89))
            XCTAssertEqual(SettlementAmountInput.parse(text, locale: locale), 1234567.89, identifier + ": " + text)
        }
    }
    func testTrailingJunkAndMalformedNumbersAreRejected() {
        let locale = Locale(identifier: "en_US")
        for text in ["abc", "12abc", "12.3.4", "--1", "1e3", "$12", "1,,234", "12,34", "1,234,56", "."] {
            XCTAssertNil(SettlementAmountInput.parse(text, locale: locale), text)
        }
    }
    func testEmptyAndWhitespaceRemainZero() {
        XCTAssertEqual(SettlementAmountInput.parse(""), 0)
        XCTAssertEqual(SettlementAmountInput.parse("   "), 0)
        XCTAssertEqual(SettlementAmountInput.parse(" 12.50 ", locale: Locale(identifier: "en_US")), 12.5)
    }
    func testSignsAreParsedThenValidatedBySettlementRules() {
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(SettlementAmountInput.parse("+12.50", locale: locale), 12.5)
        let negative = SettlementAmountInput.parse("-12.50", locale: locale)
        XCTAssertEqual(negative, -12.5)
        XCTAssertEqual(SettlementValidation.validate(fare: negative, tip: 0, expenses: []), .negativeFare)
    }
    func testNonFiniteAndOverflowCannotEnterBinding() {
        for text in ["nan", "inf", "-inf", String(repeating: "9", count: 400)] {
            XCTAssertNil(SettlementAmountInput.parse(text, locale: Locale(identifier: "en_US")))
        }
    }
    func testArabicDecimalDigitsAreSupported() {
        XCTAssertEqual(SettlementAmountInput.parse("١٢٣٫٥٠", locale: Locale(identifier: "ar_EG")), 123.5)
    }
}

final class SettlementAmountCoordinatorTests: XCTestCase {
    @MainActor func testInvalidTextKeepsOldValueButReportsInvalidity() {
        var amount = 90.0
        var valid: Bool?
        let input = AmountTextField(placeholder: "", value: Binding(get: { amount }, set: { amount = $0 }), onValidityChange: { valid = $0 })
        let coordinator = input.makeCoordinator()
        let field = UITextField()
        field.text = "abc"
        coordinator.valueChanged(field)
        XCTAssertEqual(amount, 90)
        XCTAssertEqual(valid, false)
        XCTAssertTrue(coordinator.hasInvalidText)
        coordinator.textFieldDidEndEditing(field)
        XCTAssertEqual(field.text, "abc")
        XCTAssertEqual(valid, false)
    }
    @MainActor func testCorrectingInvalidTextRestoresValidity() {
        var amount = 90.0
        var valid: Bool?
        let input = AmountTextField(placeholder: "", value: Binding(get: { amount }, set: { amount = $0 }), onValidityChange: { valid = $0 })
        let coordinator = input.makeCoordinator()
        let field = UITextField()
        field.text = "12abc"
        coordinator.valueChanged(field)
        XCTAssertEqual(valid, false)
        field.text = "12"
        coordinator.valueChanged(field)
        XCTAssertEqual(amount, 12)
        XCTAssertEqual(valid, true)
        XCTAssertFalse(coordinator.hasInvalidText)
    }
    @MainActor func testClearingAmountProducesValidZero() {
        var amount = 90.0
        var valid: Bool?
        let input = AmountTextField(placeholder: "", value: Binding(get: { amount }, set: { amount = $0 }), onValidityChange: { valid = $0 })
        let coordinator = input.makeCoordinator()
        let field = UITextField()
        field.text = ""
        coordinator.textFieldDidEndEditing(field)
        XCTAssertEqual(amount, 0)
        XCTAssertEqual(valid, true)
    }
    @MainActor func testInvalidTextIsNotClearedWhenOriginalValueWasZero() {
        var amount = 0.0
        let input = AmountTextField(placeholder: "", value: Binding(get: { amount }, set: { amount = $0 }), onValidityChange: { _ in })
        let coordinator = input.makeCoordinator()
        let field = UITextField()
        field.text = "abc"
        coordinator.valueChanged(field)
        coordinator.textFieldDidBeginEditing(field)
        XCTAssertEqual(field.text, "abc")
    }
}

final class SettlementInputSaveIntegrationTests: XCTestCase {
    @MainActor
    func fixture() throws -> (ModelContainer, SettlementFormHarness) {
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let booking = TripBookingRecord(form: NewTripFormModel())
        booking.price = 90
        booking.isCompleted = true
        context.insert(booking)
        try context.save()
        return (container, SettlementFormHarness(booking: booking, context: context))
    }
    @MainActor func testInvalidTextBlocksSaveUntilCorrectedAndReadbackMatchesInput() throws {
        let (container, form) = try fixture()
        let input = AmountTextField(placeholder: "", value: Binding(get: { form.tripFare }, set: { form.tripFare = $0 }), onValidityChange: { form.setAmountValidity($0, key: "fare") })
        let coordinator = input.makeCoordinator()
        let field = UITextField()
        field.text = "12abc"
        coordinator.valueChanged(field)
        form.saveSettlement()
        XCTAssertFalse(form.dismissed)
        XCTAssertFalse(form.booking.isPaid)
        XCTAssertEqual(form.booking.price, 90)
        XCTAssertNotNil(form.errorMessage)
        field.text = "120"
        coordinator.valueChanged(field)
        form.saveSettlement()
        XCTAssertTrue(form.dismissed)
        let readback = ModelContext(container)
        let saved = try XCTUnwrap(readback.fetch(FetchDescriptor<TripBookingRecord>()).first)
        XCTAssertEqual(saved.price, 120)
        XCTAssertTrue(saved.isPaid)
        XCTAssertTrue(saved.isCompleted)
    }
    @MainActor func testInvalidExpenseBlocksSaveButRemovingThatRowUnblocksIt() throws {
        let (_, form) = try fixture()
        let expense = TripExpenseAdjustment(isAddition: false, title: "Parking", amount: 10)
        form.expenseAdjustments = [expense]
        form.setAmountValidity(false, key: expense.id.uuidString)
        form.saveSettlement()
        XCTAssertFalse(form.dismissed)
        XCTAssertFalse(form.booking.isPaid)
        form.expenseAdjustments.removeAll()
        form.saveSettlement()
        XCTAssertTrue(form.dismissed)
        XCTAssertTrue(form.booking.isPaid)
        XCTAssertTrue(form.booking.expenseAdjustments.isEmpty)
    }
    @MainActor func testInvalidTipIndependentlyBlocksSave() throws {
        let (_, form) = try fixture()
        form.setAmountValidity(false, key: "tip")
        form.saveSettlement()
        XCTAssertFalse(form.dismissed)
        XCTAssertFalse(form.booking.isPaid)
        form.setAmountValidity(true, key: "tip")
        form.saveSettlement()
        XCTAssertTrue(form.dismissed)
    }
}

final class BusinessCardDraftTests: XCTestCase {
    @MainActor func testLocalCardReloadReadsPreviouslySavedDraft() async throws {
        CardStoreFixture.values = [:]
        CardStoreFixture.migratedEmails = []
        defer { CardStoreFixture.values = [:]; CardStoreFixture.migratedEmails = [] }
        let form = CardDraftHarness()
        form.auth.isCloudAccount = false
        form.auth.serverEntitlement = nil
        form.loadedDraftAccountKey = form.draftAccountKey
        form.draft.nickname = "Saved local nickname"
        await form.saveDraft()
        form.draft = CardDraftFixture()
        form.persistedDraft = nil
        form.hasLoaded = false
        await form.loadDraft()
        XCTAssertEqual(form.draft.nickname, "Saved local nickname")
        XCTAssertEqual(form.persistedDraft?.nickname, "Saved local nickname")
        XCTAssertEqual(CardStoreFixture.migratedEmails, [form.auth.currentEmail])
    }
    @MainActor func testLocalAndCloudAssetNamespacesDoNotMix() async throws {
        CardStoreFixture.values = [:]
        defer { CardStoreFixture.values = [:]; CardStoreFixture.migratedEmails = [] }
        let form = CardDraftHarness()
        form.auth.isCloudAccount = false
        form.auth.serverEntitlement = nil
        form.hasLoaded = false
        var local = CardDraftFixture(); local.nickname = "Local nickname"
        var cloud = CardDraftFixture(); cloud.nickname = "Cloud nickname"
        CardStoreFixture.set(try JSONEncoder().encode(local), for: .businessCard, email: form.auth.currentEmail, namespace: .local)
        CardStoreFixture.set(try JSONEncoder().encode(cloud), for: .businessCard, email: form.auth.currentEmail, namespace: .cloud)
        await form.loadDraft()
        XCTAssertEqual(form.draft.nickname, "Local nickname")
    }
    @MainActor func testMalformedCloudDataPreservesExistingCard() async {
        let form = CardDraftHarness()
        form.draft.nickname = "Existing card"
        form.persistedDraft = form.draft
        form.cloudAssetModel.loadHandler = { Data("{}".utf8) }
        await form.loadDraft()
        XCTAssertEqual(form.draft.nickname, "Existing card")
        XCTAssertEqual(form.persistedDraft?.nickname, "Existing card")
        XCTAssertNotNil(form.cloudAssetModel.errorMessage)
    }
    @MainActor func testMalformedLocalDataPreservesExistingCard() async {
        CardStoreFixture.values = [:]
        defer { CardStoreFixture.values = [:]; CardStoreFixture.migratedEmails = [] }
        let form = CardDraftHarness()
        form.auth.isCloudAccount = false
        form.auth.serverEntitlement = nil
        form.draft.nickname = "Existing local card"
        form.persistedDraft = form.draft
        CardStoreFixture.set(Data("{}".utf8), for: .businessCard, email: form.auth.currentEmail, namespace: .local)
        await form.loadDraft()
        XCTAssertEqual(form.draft.nickname, "Existing local card")
        XCTAssertNotNil(form.cloudAssetModel.errorMessage)
    }
    @MainActor func testMalformedInitialLoadDoesNotEnableBlankSave() async {
        let form = CardDraftHarness()
        form.hasLoaded = false
        var saves = 0
        form.cloudAssetModel.loadHandler = { Data("{}".utf8) }
        form.cloudAssetModel.saveHandler = { _ in saves += 1; return true }
        await form.loadDraft()
        XCTAssertFalse(form.hasLoaded)
        await form.saveDraft()
        XCTAssertEqual(saves, 0)
        XCTAssertNotNil(form.cloudAssetModel.errorMessage)
    }
    @MainActor func testDirtyDraftSkipsBackgroundReload() async {
        let form = CardDraftHarness()
        form.draft.nickname = "Unsaved nickname"
        await form.loadDraft()
        XCTAssertEqual(form.cloudAssetModel.loadCount, 0)
        XCTAssertEqual(form.draft.nickname, "Unsaved nickname")
    }
    @MainActor func testEditDuringReloadIsNotOverwritten() async throws {
        let form = CardDraftHarness()
        let started = expectation(description: "Card reload started")
        var response: CheckedContinuation<Data?, Never>?
        form.cloudAssetModel.loadHandler = {
            await withCheckedContinuation { response = $0; started.fulfill() }
        }
        let task = Task { @MainActor in await form.loadDraft() }
        await fulfillment(of: [started], timeout: 2)
        form.draft.nickname = "Typed while loading"
        var remote = CardDraftFixture(); remote.nickname = "Remote nickname"
        response?.resume(returning: try JSONEncoder().encode(remote))
        await task.value
        XCTAssertEqual(form.draft.nickname, "Typed while loading")
        XCTAssertEqual(form.persistedDraft?.nickname, "")
    }
    @MainActor func testSaveAcknowledgesSentDraftNotLaterEdits() async throws {
        let form = CardDraftHarness()
        form.draft.nickname = "Sent nickname"
        let started = expectation(description: "Card save started")
        var response: CheckedContinuation<Bool, Never>?
        var uploaded: Data?
        form.cloudAssetModel.saveHandler = { data in
            uploaded = data
            return await withCheckedContinuation { response = $0; started.fulfill() }
        }
        let task = Task { @MainActor in await form.saveDraft() }
        await fulfillment(of: [started], timeout: 2)
        form.draft.nickname = "Edited during save"
        response?.resume(returning: true)
        await task.value
        XCTAssertEqual(try JSONDecoder().decode(CardDraftFixture.self, from: XCTUnwrap(uploaded)).nickname, "Sent nickname")
        XCTAssertEqual(form.persistedDraft?.nickname, "Sent nickname")
        XCTAssertEqual(form.draft.nickname, "Edited during save")
        XCTAssertNotEqual(form.draft, form.persistedDraft)
    }
    @MainActor func testFailedReloadKeepsExistingCard() async {
        let form = CardDraftHarness()
        form.draft.nickname = "Saved nickname"
        form.persistedDraft = form.draft
        form.cloudAssetModel.loadHandler = {
            form.cloudAssetModel.errorMessage = "Fixture load failed"
            return nil
        }
        await form.loadDraft()
        XCTAssertEqual(form.draft.nickname, "Saved nickname")
        XCTAssertEqual(form.persistedDraft?.nickname, "Saved nickname")
        XCTAssertTrue(form.hasLoaded)
    }
    @MainActor func testLateReloadCannotReplaceNewerReload() async throws {
        let form = CardDraftHarness()
        let started = expectation(description: "First card reload started")
        var response: CheckedContinuation<Data?, Never>?
        var calls = 0
        var newer = CardDraftFixture(); newer.nickname = "Newest card"
        let newerData = try JSONEncoder().encode(newer)
        form.cloudAssetModel.loadHandler = {
            calls += 1
            if calls == 1 { return await withCheckedContinuation { response = $0; started.fulfill() } }
            return newerData
        }
        let task = Task { @MainActor in await form.loadDraft() }
        await fulfillment(of: [started], timeout: 2)
        await form.loadDraft()
        var older = CardDraftFixture(); older.nickname = "Old card"
        response?.resume(returning: try JSONEncoder().encode(older))
        await task.value
        XCTAssertEqual(form.draft.nickname, "Newest card")
        XCTAssertEqual(form.persistedDraft?.nickname, "Newest card")
    }
}

final class BusinessCardImageBoundaryTests: XCTestCase {
    @MainActor func imageData(color: UIColor = .red) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }.pngData()!
    }
    @MainActor func testCurrentPortraitIsApplied() async {
        let form = CardDraftHarness()
        let photo = CardPhotoFixture()
        let data = imageData()
        photo.loadHandler = { data }
        form.portraitPicker = photo
        await form.loadPortrait(photo)
        XCTAssertNotNil(form.draft.portraitData)
        XCTAssertNotNil(form.draft.portraitData.flatMap { UIImage(data: $0) })
    }
    @MainActor func testPortraitFromPreviousAccountIsDropped() async {
        let form = CardDraftHarness()
        let photo = CardPhotoFixture()
        let started = expectation(description: "Photo transfer started")
        var response: CheckedContinuation<Data?, Never>?
        photo.loadHandler = { await withCheckedContinuation { response = $0; started.fulfill() } }
        form.portraitPicker = photo
        let task = Task { @MainActor in await form.loadPortrait(photo) }
        await fulfillment(of: [started], timeout: 2)
        form.auth.currentEmail = "different-card@example.invalid"
        let existing = Data([7])
        form.draft.portraitData = existing
        response?.resume(returning: imageData())
        await task.value
        XCTAssertEqual(form.draft.portraitData, existing)
    }
    @MainActor func testOldPortraitChoiceCannotReplaceNewSelection() async {
        let form = CardDraftHarness()
        let oldPhoto = CardPhotoFixture()
        let newPhoto = CardPhotoFixture()
        let data = imageData()
        let started = expectation(description: "Old photo transfer started")
        var response: CheckedContinuation<Data?, Never>?
        oldPhoto.loadHandler = { await withCheckedContinuation { response = $0; started.fulfill() } }
        newPhoto.loadHandler = { data }
        form.portraitPicker = oldPhoto
        let task = Task { @MainActor in await form.loadPortrait(oldPhoto) }
        await fulfillment(of: [started], timeout: 2)
        form.portraitPicker = newPhoto
        await form.loadPortrait(newPhoto)
        let chosen = form.draft.portraitData
        response?.resume(returning: imageData(color: .blue))
        await task.value
        XCTAssertNotNil(chosen)
        XCTAssertEqual(form.draft.portraitData, chosen)
    }
    @MainActor func testInvalidPortraitPreservesExistingImage() async {
        let form = CardDraftHarness()
        let photo = CardPhotoFixture()
        photo.loadHandler = { Data([1,2,3]) }
        form.portraitPicker = photo
        form.draft.portraitData = Data([9])
        await form.loadPortrait(photo)
        XCTAssertEqual(form.draft.portraitData, Data([9]))
    }
    @MainActor func testAccountMismatchBlocksSavingPreviousDraft() async {
        let form = CardDraftHarness()
        var saves = 0
        form.cloudAssetModel.saveHandler = { _ in saves += 1; return true }
        form.auth.currentEmail = "different-card@example.invalid"
        await form.saveDraft()
        XCTAssertEqual(saves, 0)
    }
    @MainActor func testQRImageOnlyUpdatesItsExistingRow() {
        let form = CardDraftHarness()
        let first = CardQRFixture(name: "First")
        let second = CardQRFixture(name: "Second")
        form.draft.qrCodes = [first, second]
        let data = imageData()
        form.applyQRCodeImage(data, to: second.id, accountKey: form.draftAccountKey)
        XCTAssertNil(form.draft.qrCodes[0].imageData)
        XCTAssertEqual(form.draft.qrCodes[1].imageData, data)
    }
    @MainActor func testDeletedQRRowCannotBeRecreatedByLateImage() {
        let form = CardDraftHarness()
        let removed = CardQRFixture(name: "Removed")
        let retained = CardQRFixture(name: "Retained")
        form.draft.qrCodes = [retained]
        form.applyQRCodeImage(imageData(), to: removed.id, accountKey: form.draftAccountKey)
        XCTAssertEqual(form.draft.qrCodes, [retained])
    }
    @MainActor func testQRImageFromPreviousAccountIsDropped() {
        let form = CardDraftHarness()
        let row = CardQRFixture(name: "Retained")
        form.draft.qrCodes = [row]
        let previousKey = form.draftAccountKey
        form.auth.currentEmail = "different-card@example.invalid"
        form.applyQRCodeImage(imageData(), to: row.id, accountKey: previousKey)
        XCTAssertNil(form.draft.qrCodes[0].imageData)
    }
}

final class TripScheduleOrderingTests: XCTestCase {
    private struct Row {
        let id: String
        let day: Date
        let time: Date
        let created: Date
    }
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func ordered(_ rows: [Row]) -> [String] {
        TripScheduleSortKey.sorted(rows) {
            TripScheduleSortKey(appointmentDate: $0.day, appointmentTime: $0.time, createdAt: $0.created, id: $0.id, calendar: calendar)
        }.map(\.id)
    }
    @MainActor func testSameTimeCopiesHaveSameOrderAcrossDifferentFetchOrders() {
        let day = date("2026-10-24T00:00:00Z")
        let time = date("2026-10-24T18:10:00Z")
        let rows = (0..<4).map { Row(id: "record-\($0)", day: day, time: time, created: day.addingTimeInterval(Double($0))) }
        let expected = rows.map(\.id)
        for input in [rows, Array(rows.reversed()), [rows[2],rows[0],rows[3],rows[1]], [rows[1],rows[3],rows[0],rows[2]]] {
            XCTAssertEqual(ordered(input), expected)
        }
    }
    @MainActor func testIdenticalCreationTimesUseStableRecordID() {
        let day = date("2026-10-24T00:00:00Z")
        let rows = ["BBB", "AAA", "CCC"].map { Row(id: $0, day: day, time: day, created: day) }
        XCTAssertEqual(ordered(rows), ["AAA", "BBB", "CCC"])
        XCTAssertEqual(ordered(Array(rows.reversed())), ["AAA", "BBB", "CCC"])
    }
    @MainActor func testHiddenDateInTimePickerDoesNotOverrideVisibleClockTime() {
        let day = date("2026-10-24T00:00:00Z")
        let morning = Row(id: "09:00", day: day, time: date("2026-12-01T09:00:00Z"), created: day)
        let noon = Row(id: "12:00", day: day, time: date("2026-01-01T12:00:00Z"), created: day)
        XCTAssertEqual(ordered([noon,morning]), ["09:00", "12:00"])
    }
    @MainActor func testAppointmentDayPrecedesClockTime() {
        let earlier = date("2026-10-24T00:00:00Z")
        let later = date("2026-10-25T00:00:00Z")
        XCTAssertEqual(ordered([Row(id: "tomorrow", day: later, time: later, created: earlier),
                                Row(id: "today", day: earlier, time: earlier.addingTimeInterval(23*3600), created: earlier)]), ["today", "tomorrow"])
    }
    @MainActor func testLostSubsecondsCannotChangeOrderAfterSync() {
        let day = date("2026-10-24T00:00:00Z")
        let original = [Row(id: "BBB",day:day,time:day,created:day.addingTimeInterval(0.1)),
                        Row(id: "AAA",day:day,time:day,created:day.addingTimeInterval(0.9))]
        let downloaded = original.map { Row(id:$0.id,day:$0.day,time:$0.time,created:day) }
        XCTAssertEqual(ordered(original), ["AAA","BBB"])
        XCTAssertEqual(ordered(original), ordered(downloaded))
    }
    @MainActor func testCloudAndLocalKeysProduceIdenticalOrdering() {
        let day = date("2026-10-24T00:00:00Z")
        let time = date("2026-10-24T18:10:00Z")
        let local = ["BBB","AAA"].map { Row(id:$0,day:day,time:time,created:day.addingTimeInterval(0.4)) }
        let cloud = TripScheduleSortKey.sorted(["BBB","AAA"]) {
            TripScheduleSortKey(appointmentDate:"2026-10-24T00:00:00+00:00",appointmentTime:"2026-10-24T18:10:00Z",createdAt:"2026-10-24T00:00:00.000Z",id:$0,calendar:calendar)
        }
        XCTAssertEqual(ordered(local), cloud)
    }
}


final class InitialCloudSyncRequestTests: XCTestCase {
    private func ready(_ request: InitialCloudSyncRequest, account: String = "A", active: Bool = true,
                       allowed: Bool = true, consent: Bool = true, prompt: Bool = false) -> Bool {
        request.isReady(account: account, isActive: active, canSync: allowed,
                        hasConsent: consent, hasImportPrompt: prompt)
    }
    func testPreparationBeforeForegroundRemainsPending() {
        var request = InitialCloudSyncRequest()
        request.request(for: "A")
        XCTAssertFalse(ready(request, active: false))
        XCTAssertTrue(ready(request))
    }
    func testForegroundBeforePreparationStartsWhenPreparationFinishes() {
        var request = InitialCloudSyncRequest()
        XCTAssertFalse(ready(request))
        request.request(for: "A")
        XCTAssertTrue(ready(request))
    }
    func testConsumptionPreventsRepeatedInitialSyncOnForeground() {
        var request = InitialCloudSyncRequest()
        request.request(for: "A")
        request.consume(for: "A")
        XCTAssertFalse(ready(request, active: false))
        XCTAssertFalse(ready(request))
    }
    func testRequestCannotCrossAccounts() {
        var request = InitialCloudSyncRequest()
        request.request(for: "A")
        XCTAssertFalse(ready(request, account: "B"))
        request.consume(for: "B")
        XCTAssertTrue(ready(request))
    }
    func testConsentEntitlementAndImportPromptStillGateStartup() {
        var request = InitialCloudSyncRequest()
        request.request(for: "A")
        XCTAssertFalse(ready(request, allowed: false))
        XCTAssertFalse(ready(request, consent: false))
        XCTAssertFalse(ready(request, prompt: true))
        XCTAssertTrue(ready(request))
    }
}


final class TripExecutionPersistenceTests: XCTestCase {
    private enum WriteFailure: Error { case disk }
    @MainActor private func fixture() throws -> (ModelContainer, ModelContext, TripBookingRecord) {
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let booking = TripBookingRecord(form: NewTripFormModel())
        booking.price = 90
        context.insert(booking)
        try context.save()
        return (container, context, booking)
    }
    @MainActor func testExecutionReminderCancellationOccursOnlyAfterSuccessfulPersistence() throws {
        let (_, context, booking) = try fixture()
        var cancelledIDs: [UUID] = []
        let cancel: (UUID) -> Void = { cancelledIDs.append($0) }
        XCTAssertThrowsError(try TripExecutionState.save(booking: booking, completed: true, cancelled: false, cancelReminders: cancel) { throw WriteFailure.disk })
        XCTAssertTrue(cancelledIDs.isEmpty)
        try TripExecutionState.save(booking: booking, completed: false, cancelled: false, cancelReminders: cancel) { try context.save() }
        XCTAssertTrue(cancelledIDs.isEmpty)
        try TripExecutionState.save(booking: booking, completed: true, cancelled: false, cancelReminders: cancel) {
            XCTAssertTrue(cancelledIDs.isEmpty)
            try context.save()
        }
        XCTAssertEqual(cancelledIDs, [booking.id])
        try TripExecutionState.save(booking: booking, completed: false, cancelled: true, cancelReminders: cancel) { try context.save() }
        XCTAssertEqual(cancelledIDs, [booking.id, booking.id])
    }
    func testReminderCancellationTargetsOnlyBothRemindersForOneTrip() {
        let id = UUID()
        XCTAssertEqual(TripReminderScheduler.identifiers(for: id), ["trip-reminder-\(id.uuidString)-1", "trip-reminder-\(id.uuidString)-2"])
        XCTAssertNotEqual(TripReminderScheduler.identifiers(for: id), TripReminderScheduler.identifiers(for: UUID()))
    }
    @MainActor func testCompletedExecutionPersistsAndReadsBack() throws {
        let (container, context, booking) = try fixture()
        try TripExecutionState.save(booking: booking, completed: true, cancelled: false) { try context.save() }
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TripBookingRecord>()).first)
        XCTAssertTrue(saved.isCompleted)
        XCTAssertFalse(saved.isCancelled)
        XCTAssertFalse(saved.isPaid)
        XCTAssertEqual(saved.price, 90)
    }
    @MainActor func testFailedCompletionRestoresOnlyExecutionFields() throws {
        let (_, _, booking) = try fixture()
        let previousDate = booking.updatedAt
        booking.memo = "Keep pending memo"
        booking.tip = 15
        booking.isPaid = true
        XCTAssertThrowsError(try TripExecutionState.save(booking: booking, completed: true, cancelled: false) {
            XCTAssertTrue(booking.isCompleted)
            throw WriteFailure.disk
        })
        XCTAssertFalse(booking.isCompleted)
        XCTAssertFalse(booking.isCancelled)
        XCTAssertEqual(booking.updatedAt, previousDate)
        XCTAssertEqual(booking.memo, "Keep pending memo")
        XCTAssertEqual(booking.tip, 15)
        XCTAssertTrue(booking.isPaid)
    }
    @MainActor func testFailedRestorePreservesCancelledStateAndNilTimestamp() throws {
        let (_, _, booking) = try fixture()
        booking.isCancelled = true
        booking.updatedAt = nil
        XCTAssertThrowsError(try TripExecutionState.save(booking: booking, completed: false, cancelled: false) { throw WriteFailure.disk })
        XCTAssertTrue(booking.isCancelled)
        XCTAssertFalse(booking.isCompleted)
        XCTAssertNil(booking.updatedAt)
    }
    @MainActor func testRetryAfterFailedCompletionPersistsConfirmedState() throws {
        let (container, context, booking) = try fixture()
        XCTAssertThrowsError(try TripExecutionState.save(booking: booking, completed: true, cancelled: false) { throw WriteFailure.disk })
        try TripExecutionState.save(booking: booking, completed: false, cancelled: true) { try context.save() }
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TripBookingRecord>()).first)
        XCTAssertFalse(saved.isCompleted)
        XCTAssertTrue(saved.isCancelled)
    }
    @MainActor func testListFailureDoesNotOfferSettlement() throws {
        let (_, _, booking) = try fixture()
        let form = ListCompletionHarness(booking: booking) { throw WriteFailure.disk }
        form.requestCompletion(for: booking)
        XCTAssertNil(form.completionBooking)
        XCTAssertNotNil(form.completionErrorMessage)
        XCTAssertFalse(booking.isCompleted)
    }
    @MainActor func testListSuccessOffersSettlementAfterPersistence() throws {
        let (_, context, booking) = try fixture()
        let form = ListCompletionHarness(booking: booking) { try context.save() }
        form.requestCompletion(for: booking)
        XCTAssertTrue(form.completionBooking === booking)
        XCTAssertNil(form.completionErrorMessage)
        XCTAssertTrue(booking.isCompleted)
    }
    @MainActor func testDetailFailureDoesNotOfferSettlement() throws {
        let (_, _, booking) = try fixture()
        let form = DetailCompletionHarness(booking: booking) { throw WriteFailure.disk }
        form.completeTrip()
        XCTAssertFalse(form.isShowingCompletionSettlementPrompt)
        XCTAssertNotNil(form.errorMessage)
        XCTAssertFalse(booking.isCompleted)
    }
    @MainActor func testDetailSuccessOffersSettlementAfterPersistence() throws {
        let (_, context, booking) = try fixture()
        let form = DetailCompletionHarness(booking: booking) { try context.save() }
        form.completeTrip()
        XCTAssertTrue(form.isShowingCompletionSettlementPrompt)
        XCTAssertNil(form.errorMessage)
        XCTAssertTrue(booking.isCompleted)
    }
    @MainActor func testCardCancellationFailurePreservesCompletedState() throws {
        let (_, _, booking) = try fixture()
        booking.isCompleted = true
        let form = CardCancellationHarness(booking: booking) { throw WriteFailure.disk }
        form.setCancelled(true)
        XCTAssertFalse(booking.isCancelled)
        XCTAssertTrue(booking.isCompleted)
        XCTAssertNotNil(form.executionErrorMessage)
    }
    @MainActor func testCardCancellationSuccessPersistsAndClearsCompleted() throws {
        let (container, context, booking) = try fixture()
        booking.isCompleted = true
        let form = CardCancellationHarness(booking: booking) { try context.save() }
        form.setCancelled(true)
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TripBookingRecord>()).first)
        XCTAssertTrue(saved.isCancelled)
        XCTAssertFalse(saved.isCompleted)
        XCTAssertNil(form.executionErrorMessage)
    }
}

final class FlightTerminalParsingTests: XCTestCase {
    @MainActor private func lookup(_ result: [String: Any]) async throws -> [VariFlightLookupResult] {
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "result": result])
        let response = String(decoding: data, as: UTF8.self)
        SyncFixtureProtocol.handle = { $0.respond(response) }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer { SyncFixtureProtocol.handle = nil; URLProtocol.unregisterClass(SyncFixtureProtocol.self) }
        return try await VariFlightClient().lookupCandidates(flightNumber: "UA1743", flightDate: Date(timeIntervalSince1970: 1792886400), cloudAccessToken: "fixture-only")
    }
    private func flight(_ extras: [String: Any] = [:]) -> [String: Any] {
        var fields: [String: Any] = ["FlightCompany":"United", "FlightDept":"IAH", "FlightArr":"LAX", "FlightDeptimePlanDate":"16:30", "FlightArrtimePlanDate":"18:07"]
        fields.merge(extras) { _, new in new }
        return fields
    }
    @MainActor func testProviderFlightHTerminalAndFlightTerminalKeys() async throws {
        let rows = try await lookup(["structuredContent":flight(["FlightHTerminal":"C", "FlightTerminal":"T7"])])
        XCTAssertEqual(rows.first?.departureTerminal, "C")
        XCTAssertEqual(rows.first?.arrivalTerminal, "T7")
    }
    @MainActor func testProviderPythonStyleTextKeepsTerminalSides() async throws {
        let text = "{'FlightCompany': 'United', 'FlightDept': 'IAH', 'FlightArr': 'LAX', 'FlightDeptimePlanDate': '16:30', 'FlightArrtimePlanDate': '18:07', 'FlightHTerminal': 'C', 'FlightTerminal': 'T7', 'DepTerminalLat': '29.983334', 'ArrTerminalLat': '33.943398'}"
        let rows = try await lookup(["content":[["type":"text", "text":text]]])
        XCTAssertEqual(rows.first?.departureTerminal, "C")
        XCTAssertEqual(rows.first?.arrivalTerminal, "T7")
    }
    @MainActor func testArrivalProviderFieldNeverFillsDepartureSlot() async throws {
        let text = "FlightDept: IAH\nFlightArr: LAX\nFlightTerminal: T7\nDepTerminalLat: 29.98"
        let rows = try await lookup(["content":[["type":"text", "text":text]]])
        XCTAssertNil(rows.first?.departureTerminal)
        XCTAssertEqual(rows.first?.arrivalTerminal, "T7")
    }
    @MainActor func testStringTerminalsRemainOnCorrectSides() async throws {
        let rows = try await lookup(["structuredContent":flight(["FlightDeptTerminal":"C", "FlightArrTerminal":"7"])])
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.departureTerminal, "C")
        XCTAssertEqual(row.arrivalTerminal, "7")
    }
    @MainActor func testNumericTerminalsAreNotDropped() async throws {
        let rows = try await lookup(["structuredContent":flight(["departureTerminal":3, "arrivalTerminal":7])])
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.departureTerminal, "3")
        XCTAssertEqual(row.arrivalTerminal, "7")
    }
    @MainActor func testDuplicateSummaryDoesNotDiscardTerminalDetails() async throws {
        let detailed = try JSONSerialization.data(withJSONObject: flight(["FlightDeptTerminal":"C", "FlightArrTerminal":"7"]))
        let rows = try await lookup(["structuredContent":flight(), "content":[["type":"text", "text":String(decoding:detailed,as:UTF8.self)]]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.departureTerminal, "C")
        XCTAssertEqual(rows.first?.arrivalTerminal, "7")
    }
    @MainActor func testChineseTerminalKeysAreRecognized() async throws {
        let rows = try await lookup(["structuredContent":flight(["出发航站楼":"C", "到达航站楼":"7"])])
        XCTAssertEqual(rows.first?.departureTerminal, "C")
        XCTAssertEqual(rows.first?.arrivalTerminal, "7")
    }
    @MainActor func testNullTerminalDoesNotBecomeZeroOrBoolean() async throws {
        let rows = try await lookup(["structuredContent":flight(["departureTerminal":NSNull(), "arrivalTerminal":false])])
        XCTAssertNil(rows.first?.departureTerminal)
        XCTAssertNil(rows.first?.arrivalTerminal)
    }
    @MainActor func testDifferentLegsKeepTheirOwnTerminals() async throws {
        var second = flight(["FlightDeptTerminal":"B", "FlightArrTerminal":"8"])
        second["FlightDept"] = "SFO"
        let rows = try await lookup(["structuredContent":[flight(["FlightDeptTerminal":"C", "FlightArrTerminal":"7"]), second]])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first(where: { $0.departureAirport == "IAH" })?.departureTerminal, "C")
        XCTAssertEqual(rows.first(where: { $0.departureAirport == "IAH" })?.arrivalTerminal, "7")
        XCTAssertEqual(rows.first(where: { $0.departureAirport == "SFO" })?.departureTerminal, "B")
        XCTAssertEqual(rows.first(where: { $0.departureAirport == "SFO" })?.arrivalTerminal, "8")
    }
    @MainActor func testTerminalDetailsSurviveSavedSnapshotRoundTrip() async throws {
        let rows = try await lookup(["structuredContent":flight(["terminal":"C", "FlightArrTerminal":"7"])])
        let snapshot = SavedFlightSelection(flightNumber:"UA1743", flightDate:Date(timeIntervalSince1970:1792886400), selected:try XCTUnwrap(rows.first))
        let read = try JSONDecoder().decode(SavedFlightSelection.self,from:JSONEncoder().encode(snapshot))
        XCTAssertEqual(read.selected.departureTerminal, "C")
        XCTAssertEqual(read.selected.arrivalTerminal, "7")
    }
}


final class SavedFlightDisplayRefreshTests: XCTestCase {
    @MainActor private func fixtures() -> [any SavedFlightDisplayHarness] {
        [TripManagementCardDisplayHarness(), TripBrowseViewDisplayHarness(), CloudTripManagementCardDisplayHarness(), CloudTripDetailViewDisplayHarness()]
    }
    private func snapshot(terminal: String?, flight: String = "UA1743") -> SavedFlightSelection {
        SavedFlightSelection(flightNumber: flight, flightDate: Date(timeIntervalSince1970: 1792800000), selected:
            VariFlightLookupResult(airlineName:"Fixture",departureAirport:"IAH",arrivalAirport:"LAX",departureTerminal:"C",arrivalTerminal:terminal,departureTime:"16:30",estimatedArrivalTime:"18:07",baggageCarousel:nil))
    }
    @MainActor func testDownloadedSnapshotRefreshesAllFourVisibleViews() async {
        for form in fixtures() {
            form.setSnapshot(snapshot(terminal:nil)); form.refreshSavedFlightDisplay(); await form.refreshTask?.value
            XCTAssertNil(form.flightLookupResult?.arrivalTerminal)
            form.setSnapshot(snapshot(terminal:"T7")); form.refreshSavedFlightDisplay(); await form.refreshTask?.value
            XCTAssertEqual(form.flightLookupResult?.departureTerminal,"C")
            XCTAssertEqual(form.flightLookupResult?.arrivalTerminal,"T7")
        }
    }
    @MainActor func testRemovedSnapshotClearsOldResultAndPickerWithoutLookup() async {
        for form in fixtures() {
            form.setSnapshot(snapshot(terminal:"T7")); form.refreshSavedFlightDisplay(); await form.refreshTask?.value
            form.flightLookupError = "Old error"
            form.flightCandidates = [snapshot(terminal:"T7").selected]
            form.isChoosingFlight = true
            form.setSnapshot(nil); form.refreshSavedFlightDisplay()
            XCTAssertNil(form.flightLookupResult)
            XCTAssertNil(form.flightLookupError)
            XCTAssertTrue(form.flightCandidates.isEmpty)
            XCTAssertFalse(form.isChoosingFlight)
            XCTAssertEqual(form.departureTimeZoneLabel, "")
        }
    }
    @MainActor func testChangedFlightNumberNeverDisplaysOldSnapshot() async {
        for form in fixtures() {
            form.setSnapshot(snapshot(terminal:"T7")); form.refreshSavedFlightDisplay(); await form.refreshTask?.value
            form.setFlightNumber("UA9999"); form.refreshSavedFlightDisplay()
            XCTAssertNil(form.flightLookupResult)
        }
    }
    @MainActor func testRemoteRefreshPreservesCollapsedAndExpandedChoices() async {
        for form in fixtures() {
            form.isFlightExpanded = false
            form.setSnapshot(snapshot(terminal:"T7")); form.refreshSavedFlightDisplay(); await form.refreshTask?.value
            XCTAssertFalse(form.isFlightExpanded)
            form.isFlightExpanded = true
            form.setSnapshot(snapshot(terminal:"8")); form.refreshSavedFlightDisplay(); await form.refreshTask?.value
            XCTAssertTrue(form.isFlightExpanded)
        }
    }
    @MainActor func testContextRejectsWrongDateRouteAndFinishedTrip() {
        let saved = snapshot(terminal:"T7")
        func context(date: Date = Date(timeIntervalSince1970: 1792800000), origin: String = "LAX Airport", allowed: Bool = true) -> SavedFlightDisplayContext {
            SavedFlightDisplayContext(flightNumber:"UA1743",flightDate:date,serviceType:"接机",locationStart:origin,locationEnd:"Hotel",snapshot:saved,canDisplay:allowed)
        }
        XCTAssertNotNil(context().selection)
        XCTAssertNil(context(date: Date(timeIntervalSince1970:1792886400)).selection)
        XCTAssertNil(context(origin:"SFO Airport").selection)
        XCTAssertNil(context(allowed:false).selection)
    }
    @MainActor func testOlderTimeZoneCompletionCannotOverwriteNewerSnapshot() async {
        let form = TripManagementCardDisplayHarness()
        var held: CheckedContinuation<String?, Never>?
        FlightDisplayZoneFixture.handler = { airport in
            if airport == "IAH" { return await withCheckedContinuation { held = $0 } }
            return "New zone"
        }
        defer { FlightDisplayZoneFixture.handler = nil }
        form.setSnapshot(snapshot(terminal:"T7")); form.refreshSavedFlightDisplay()
        let oldTask = form.refreshTask
        while held == nil { await Task.yield() }
        form.setSnapshot(nil); form.refreshSavedFlightDisplay()
        held?.resume(returning:"Old zone")
        await oldTask?.value
        XCTAssertNil(form.flightLookupResult)
        XCTAssertEqual(form.departureTimeZoneLabel, "")
    }
}


final class FlightReadOnlyStaleLookupTests: XCTestCase {
    @MainActor private func check(_ form: any FlightReadOnlyHarness, fails: Bool) async {
        let started = expectation(description: "Old provider request waiting")
        var response: CheckedContinuation<[VariFlightLookupResult], Error>?
        let old = VariFlightLookupResult(airlineName:"Old",departureAirport:"SFO",arrivalAirport:"LAX",departureTerminal:"1",arrivalTerminal:"7",departureTime:"14:00",estimatedArrivalTime:"15:00",baggageCarousel:nil)
        let current = VariFlightLookupResult(airlineName:"Latest sync",departureAirport:"IAH",arrivalAirport:"LAX",departureTerminal:"C",arrivalTerminal:"T7",departureTime:"16:30",estimatedArrivalTime:"18:07",baggageCarousel:nil)
        FlightRaceClient.handler = { _ in try await withCheckedThrowingContinuation { response = $0; started.fulfill() } }
        defer { FlightRaceClient.handler = nil }
        form.lookupFlight(forceRefresh:true)
        await fulfillment(of:[started],timeout:2)
        // Simulates the already-tested display-context observer receiving a
        // newer saved snapshot while this provider response is still pending.
        form.savedFlightDisplayContext += 1
        form.flightLookupResult = current
        if fails { response?.resume(throwing:URLError(.timedOut)) }
        else { response?.resume(returning:[old]) }
        await form.lookupTask?.value
        if form.directory.continuation != nil { form.directory.finish(saved:true) }
        await form.selectionTask?.value
        XCTAssertEqual(form.flightLookupResult,current,"Old query must not replace the latest synchronized snapshot")
        XCTAssertEqual(form.directory.callCount,0,"Obsolete query must not persist an older flight selection")
        XCTAssertNil(form.flightLookupError,"An obsolete request failure must not hide valid synchronized data")
        XCTAssertFalse(form.isLookingUpFlight)
    }
    @MainActor func testCardDropsOldSuccessAfterSnapshotChanges() async { await check(FlightManagementCardHarness(),fails:false) }
    @MainActor func testDetailDropsOldSuccessAfterSnapshotChanges() async { await check(FlightDetailViewHarness(),fails:false) }
    @MainActor func testCardDropsOldFailureAfterSnapshotChanges() async { await check(FlightManagementCardHarness(),fails:true) }
    @MainActor func testDetailDropsOldFailureAfterSnapshotChanges() async { await check(FlightDetailViewHarness(),fails:true) }
}


final class FlightReadOnlyStaleSelectionTests: XCTestCase {
    @MainActor private func check(_ form: any FlightReadOnlyHarness) async {
        let waiting = expectation(description:"Selection waiting for time zone")
        var zone: CheckedContinuation<String?, Never>?
        let old = VariFlightLookupResult(airlineName:"Old",departureAirport:"SFO",arrivalAirport:"LAX",departureTerminal:"1",arrivalTerminal:"7",departureTime:"14:00",estimatedArrivalTime:"15:00",baggageCarousel:nil)
        let current = VariFlightLookupResult(airlineName:"Synced",departureAirport:"IAH",arrivalAirport:"LAX",departureTerminal:"C",arrivalTerminal:"T7",departureTime:"16:30",estimatedArrivalTime:"18:07",baggageCarousel:nil)
        FlightRaceClient.handler = { _ in [old] }
        FlightRaceTimeZone.handler = { airport in
            if airport == "SFO" { return await withCheckedContinuation { zone=$0;waiting.fulfill() } }
            return "New zone"
        }
        defer { FlightRaceClient.handler=nil;FlightRaceTimeZone.handler=nil;form.directory.started=nil }
        form.directory.started = { form.directory.finish(saved:true) }
        form.lookupFlight(forceRefresh:true)
        await form.lookupTask?.value
        await fulfillment(of:[waiting],timeout:2)
        form.savedFlightDisplayContext += 1
        form.flightLookupResult=current
        zone?.resume(returning:"Old zone")
        await form.selectionTask?.value
        XCTAssertEqual(form.directory.callCount,0)
        XCTAssertEqual(form.flightLookupResult,current)
        XCTAssertNil(form.flightLookupError)
        XCTAssertFalse(form.isLookingUpFlight)
    }
    @MainActor func testCardDropsSelectionAfterNewSnapshotDuringTimeZoneWait() async { await check(FlightManagementCardHarness()) }
    @MainActor func testDetailDropsSelectionAfterNewSnapshotDuringTimeZoneWait() async { await check(FlightDetailViewHarness()) }
}


final class LocalFlightSnapshotPersistenceTests: XCTestCase {
    private enum WriteFailure: Error { case disk }
    private func result(_ terminal: String) -> VariFlightLookupResult {
        VariFlightLookupResult(airlineName:"Fixture",departureAirport:"IAH",arrivalAirport:"LAX",departureTerminal:"C",arrivalTerminal:terminal,departureTime:"16:30",estimatedArrivalTime:"18:07",baggageCarousel:"4")
    }
    @MainActor private func fixture() throws -> (ModelContainer, ModelContext, TripBookingRecord) {
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,isStoredInMemoryOnly:true)])
        let context = ModelContext(container)
        var form = NewTripFormModel()
        form.flightInfo="UA1743";form.locationStart="LAX Airport";form.locationEnd="Hotel"
        let booking=TripBookingRecord(form:form)
        booking.flightSelectionSnapshotJSON="legacy raw snapshot"
        booking.flightDepartureTime="14:00";booking.flightEstimatedArrivalTime="15:00"
        booking.flightArrivalTerminal="old terminal";booking.flightBaggageCarousel="old belt"
        context.insert(booking);try context.save()
        booking.memo="Keep pending memo";booking.tip=15
        return (container,context,booking)
    }
    @MainActor private func checkFailure(detail: Bool, empty: Bool) async throws {
        let (_,_,booking)=try fixture()
        if empty {
            booking.flightSelectionSnapshotJSON="";booking.flightDepartureTime=nil
            booking.flightEstimatedArrivalTime=nil;booking.flightArrivalTerminal=nil
            booking.flightBaggageCarousel=nil;booking.updatedAt=nil
        }
        let raw=booking.flightSelectionSnapshotJSON
        let departure=booking.flightDepartureTime, arrival=booking.flightEstimatedArrivalTime
        let terminal=booking.flightArrivalTerminal, baggage=booking.flightBaggageCarousel, updated=booking.updatedAt
        if detail {
            let form=FlightDetailPersistenceHarness(booking:booking) { throw WriteFailure.disk }
            form.flightLookupResult=empty ? nil : result("old")
            let prior=form.flightLookupResult
            form.selectFlight(result("T7"));await form.zoneTask?.value
            XCTAssertEqual(form.flightLookupResult,prior)
            XCTAssertNotNil(form.flightLookupError)
        } else {
            let form=FlightCardPersistenceHarness(booking:booking) { throw WriteFailure.disk }
            form.flightLookupResult=empty ? nil : result("old")
            let prior=form.flightLookupResult
            form.selectFlight(result("T7"));await form.zoneTask?.value
            XCTAssertEqual(form.flightLookupResult,prior)
            XCTAssertNotNil(form.flightLookupError)
        }
        XCTAssertEqual(booking.flightSelectionSnapshotJSON,raw)
        XCTAssertEqual(booking.flightDepartureTime,departure)
        XCTAssertEqual(booking.flightEstimatedArrivalTime,arrival)
        XCTAssertEqual(booking.flightArrivalTerminal,terminal)
        XCTAssertEqual(booking.flightBaggageCarousel,baggage)
        XCTAssertEqual(booking.updatedAt,updated)
        XCTAssertEqual(booking.memo,"Keep pending memo")
        XCTAssertEqual(booking.tip,15)
    }
    @MainActor private func checkSuccess(detail: Bool, retry: Bool) async throws {
        let (container,context,booking)=try fixture()
        var attempts=0
        let persist: () throws -> Void = {
            attempts += 1
            if retry && attempts == 1 { throw WriteFailure.disk }
            try context.save()
        }
        if detail {
            let form=FlightDetailPersistenceHarness(booking:booking,persist:persist)
            if retry { form.selectFlight(result("wrong"));await form.zoneTask?.value }
            form.selectFlight(result("T7"));await form.zoneTask?.value
            XCTAssertEqual(form.flightLookupResult?.arrivalTerminal,"T7")
            XCTAssertNil(form.flightLookupError)
        } else {
            let form=FlightCardPersistenceHarness(booking:booking,persist:persist)
            if retry { form.selectFlight(result("wrong"));await form.zoneTask?.value }
            form.selectFlight(result("T7"));await form.zoneTask?.value
            XCTAssertEqual(form.flightLookupResult?.arrivalTerminal,"T7")
            XCTAssertNil(form.flightLookupError)
        }
        let saved=try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TripBookingRecord>()).first)
        let snapshot=try JSONDecoder().decode(SavedFlightSelection.self,from:Data(saved.flightSelectionSnapshotJSON.utf8))
        XCTAssertEqual(snapshot.selected.departureTerminal,"C")
        XCTAssertEqual(snapshot.selected.arrivalTerminal,"T7")
        XCTAssertEqual(saved.flightArrivalTerminal,"T7")
        XCTAssertEqual(saved.flightBaggageCarousel,"4")
        XCTAssertEqual(saved.memo,"Keep pending memo")
        XCTAssertEqual(saved.tip,15)
    }
    @MainActor func testCardFailureRestoresExistingSnapshot() async throws { try await checkFailure(detail:false,empty:false) }
    @MainActor func testDetailFailureRestoresExistingSnapshot() async throws { try await checkFailure(detail:true,empty:false) }
    @MainActor func testCardFailureRestoresEmptyFieldsAndNilTimestamp() async throws { try await checkFailure(detail:false,empty:true) }
    @MainActor func testDetailFailureRestoresEmptyFieldsAndNilTimestamp() async throws { try await checkFailure(detail:true,empty:true) }
    @MainActor func testCardSuccessPersistsAndReadsBack() async throws { try await checkSuccess(detail:false,retry:false) }
    @MainActor func testDetailSuccessPersistsAndReadsBack() async throws { try await checkSuccess(detail:true,retry:false) }
    @MainActor func testCardRetryClearsErrorAndSavesConfirmedSelection() async throws { try await checkSuccess(detail:false,retry:true) }
    @MainActor func testDetailRetryClearsErrorAndSavesConfirmedSelection() async throws { try await checkSuccess(detail:true,retry:true) }
}

/// Keeps committed server rows between retries, including a lost success response.
final class OfflineRetryRegressionTests: XCTestCase {
    @MainActor private func runRetry(failure: String, editDuringUpload: Bool = false, previouslySynced: Bool = false) async throws {
        let oldScope = DataOwnership.activeScope
        let email = "isolated-offline-retry@example.invalid"
        DataOwnership.activateCloud(email: email)
        defer {
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let sentAt = Date(timeIntervalSince1970: 1700000000)
        let editedAt = sentAt.addingTimeInterval(60)
        let agency = TravelAgency(agencyCode: "QA", name: "Agency before", createdAt: sentAt, updateAt: sentAt)
        let customer = Custumer(name: "Customer before", email: "", csource: "", type: 1, createdAt: sentAt, updateAt: sentAt)
        let trip = TripBookingRecord(form: NewTripFormModel())
        trip.createdAt = sentAt;trip.updatedAt = sentAt;trip.memo = "Memo before"
        trip.locationStops = ["Fixture stop"]
        let expense = TripExpenseAdjustment(isAddition: true, title: "Parking", amount: 12)
        trip.expenseAdjustments = [expense]
        let previousBaseline = sentAt.addingTimeInterval(-60)
        if previouslySynced {
            agency.syncBaseUpdatedAt = previousBaseline
            customer.syncBaseUpdatedAt = previousBaseline
            trip.syncBaseUpdatedAt = previousBaseline
        }
        context.insert(agency);context.insert(customer);context.insert(trip)
        context.insert(Connect(connectlable: "Phone", connecttype: "5550100", isDefault: true, customer: customer))
        context.insert(Address(addlable: "Home", addresses: "Fixture address", isDefault: true, customer: customer))
        try context.save()
        var rows: [String: [String: [String: Any]]] = [:]
        var failed = false
        var edited = false
        var authRequests = 0
        func body(_ request: URLRequest) -> Data {
            if let data = request.httpBody { return data }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open();defer { stream.close() }
            var data = Data();var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break };data.append(contentsOf: buffer.prefix(count))
            }
            return data
        }
        SyncFixtureProtocol.handle = { fixture in
            let path = fixture.request.url!.path
            let table = fixture.request.url!.lastPathComponent
            let method = fixture.request.httpMethod ?? "GET"
            if path == "/auth/v1/user" {
                authRequests += 1
                if failure == "final-auth", authRequests > 1, !failed {
                    failed = true;fixture.client?.urlProtocol(fixture, didFailWithError: URLError(.networkConnectionLost));return
                }
                fixture.respond("{\"id\":\"00000000-0000-0000-0000-000000000001\"}");return
            }
            if failure == "pull", table == "customers", method == "GET", !failed {
                failed = true;fixture.client?.urlProtocol(fixture, didFailWithError: URLError(.notConnectedToInternet));return
            }
            if failure == "expenses", table == "trip_expenses", method == "PATCH", !failed {
                failed = true;fixture.client?.urlProtocol(fixture, didFailWithError: URLError(.networkConnectionLost));return
            }
            if method == "POST", let posted = (try? JSONSerialization.jsonObject(with: body(fixture.request))) as? [[String: Any]] {
                for row in posted {
                    if let id = row["id"] as? String { rows[table, default: [:]][id] = row }
                }
                if !failed, (table == "trips" && failure == "lost-response") || (table == "customers" && failure == "lost-customer-response") {
                    Task { @MainActor in
                        if editDuringUpload && !edited {
                            edited = true
                            agency.name = "Agency edited";agency.updateAt = editedAt
                            customer.name = "Customer edited";customer.updateAt = editedAt
                            trip.memo = "Memo edited";trip.updatedAt = editedAt
                            try context.save()
                        }
                        failed = true
                        fixture.client?.urlProtocol(fixture, didFailWithError: URLError(.networkConnectionLost))
                    }
                    return
                }
                fixture.respond("[]");return
            }
            if method == "PATCH" {
                // Child replacement first marks prior rows deleted, then upserts stable IDs.
                for id in Array(rows[table, default: [:]].keys) { rows[table]?[id]?["deleted_at"] = "2026-10-25T00:00:00Z" }
                fixture.respond("[]");return
            }
            let active = Array(rows[table, default: [:]].values)
            fixture.respond(String(decoding: try! JSONSerialization.data(withJSONObject: active), as: UTF8.self))
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        do {
            _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
            XCTFail("Expected injected connection loss")
        } catch { XCTAssertTrue(failed) }
        XCTAssertEqual(agency.syncBaseUpdatedAt, previouslySynced ? previousBaseline : nil)
        XCTAssertEqual(customer.syncBaseUpdatedAt, previouslySynced ? previousBaseline : nil)
        XCTAssertEqual(trip.syncBaseUpdatedAt, previouslySynced ? previousBaseline : nil)
        XCTAssertEqual(trip.locationStops, ["Fixture stop"])
        XCTAssertEqual(trip.expenseAdjustments, [expense])
        _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
        var acknowledgedAgencyAt = editDuringUpload ? editedAt : sentAt
        var acknowledgedCustomerAt = acknowledgedAgencyAt
        var acknowledgedTripAt = acknowledgedAgencyAt
        if previouslySynced {
            let conflicts = try context.fetch(FetchDescriptor<CloudSyncConflict>())
            let expectedTables: Set<String> = failure == "lost-customer-response"
                ? ["travel_agencies", "customers"] : ["travel_agencies", "customers", "trips"]
            XCTAssertEqual(Set(conflicts.map(\.tableName)), expectedTables)
            XCTAssertEqual(conflicts.count, expectedTables.count)
            XCTAssertEqual(trip.locationStops, ["Fixture stop"])
            XCTAssertEqual(trip.expenseAdjustments, [expense])
            XCTAssertEqual(customer.connecttype.map(\.connecttype), ["5550100"])
            XCTAssertEqual(customer.addresses.map(\.addresses), ["Fixture address"])
            for conflict in conflicts {
                XCTAssertEqual(conflict.ownerScope, DataOwnership.activeScope)
                XCTAssertEqual(conflict.remoteUpdatedAt, sentAt)
                XCTAssertEqual(conflict.localUpdatedAt, editDuringUpload ? editedAt : sentAt)
                try SupabaseDataSync.resolveConflict(conflict, keepRemote: false, context: context)
            }
            acknowledgedAgencyAt = agency.updateAt
            acknowledgedCustomerAt = customer.updateAt
            acknowledgedTripAt = try XCTUnwrap(trip.updatedAt)
            XCTAssertGreaterThan(acknowledgedAgencyAt, sentAt)
            XCTAssertGreaterThan(acknowledgedCustomerAt, sentAt)
            if expectedTables.contains("trips") { XCTAssertGreaterThan(acknowledgedTripAt, sentAt) }
            _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
        }
        XCTAssertEqual(agency.name, editDuringUpload ? "Agency edited" : "Agency before")
        XCTAssertEqual(customer.name, editDuringUpload ? "Customer edited" : "Customer before")
        XCTAssertEqual(trip.memo, editDuringUpload ? "Memo edited" : "Memo before")
        XCTAssertEqual(agency.syncBaseUpdatedAt, acknowledgedAgencyAt)
        XCTAssertEqual(customer.syncBaseUpdatedAt, acknowledgedCustomerAt)
        XCTAssertEqual(trip.syncBaseUpdatedAt, acknowledgedTripAt)
        XCTAssertEqual(trip.locationStops, ["Fixture stop"], "An incomplete remote child upload must not erase the retained stop on retry")
        XCTAssertEqual(trip.expenseAdjustments, [expense], "An incomplete remote child upload must not erase expenses on retry")
        XCTAssertEqual(customer.connecttype.map(\.connecttype), ["5550100"])
        XCTAssertEqual(customer.addresses.map(\.addresses), ["Fixture address"])
        for table in ["travel_agencies", "customers", "customer_contacts", "customer_addresses", "trips", "trip_stops", "trip_expenses"] {
            let active = rows[table, default: [:]].values.filter { $0["deleted_at"] is NSNull }
            XCTAssertEqual(active.count, 1, "Retry must converge to one active row in \(table)")
        }
        XCTAssertTrue(try context.fetch(FetchDescriptor<CloudSyncConflict>()).isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TripBookingRecord>()), 1)
        let readback = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TripBookingRecord>()).first)
        XCTAssertEqual(readback.expenseAdjustments, [expense])
    }
    @MainActor func testExistingCustomerLostResponsePreservesChildrenUntilKeepLocal() async throws { try await runRetry(failure: "lost-customer-response", editDuringUpload: false, previouslySynced: true) }
    @MainActor func testExistingTripLostResponsePreservesChildrenUntilKeepLocal() async throws { try await runRetry(failure: "lost-response", editDuringUpload: false, previouslySynced: true) }
    @MainActor func testExistingTripExpenseFailurePreservesChildrenUntilKeepLocal() async throws { try await runRetry(failure: "expenses", editDuringUpload: false, previouslySynced: true) }
    @MainActor func testExistingRecordsFinalFailureCanResolveKeepingLocal() async throws { try await runRetry(failure: "final-auth", editDuringUpload: false, previouslySynced: true) }
    @MainActor func testExistingRecordsInFlightEditSurvivesRetryAndResolution() async throws { try await runRetry(failure: "lost-response", editDuringUpload: true, previouslySynced: true) }
    @MainActor func testOfflineDuringPullRetainsDataAndRetryConverges() async throws { try await runRetry(failure: "pull") }
    @MainActor func testLostCustomerSuccessResponseRetainsContactsOnRetry() async throws { try await runRetry(failure: "lost-customer-response") }
    @MainActor func testLostTripSuccessResponseRetainsChildrenOnRetry() async throws { try await runRetry(failure: "lost-response") }
    @MainActor func testLostTripResponseRetainsEditsMadeDuringUpload() async throws { try await runRetry(failure: "lost-response", editDuringUpload: true) }
    @MainActor func testConnectionLossBeforeExpensesRetainsChildrenOnRetry() async throws { try await runRetry(failure: "expenses") }
    @MainActor func testFinalConnectionLossRetriesWithoutDuplicates() async throws { try await runRetry(failure: "final-auth") }
}

final class CustomerTripConflictAcceptanceTests: XCTestCase {
    @MainActor private func runConflict(table: String, remoteDeleted: Bool, keepRemote: Bool,
                                       editingCustomer: Bool = false, wrongScope: Bool = false, newerDeletion: Bool = false) async throws {
        let oldScope = DataOwnership.activeScope
        let email = "isolated-customer-trip-conflict@example.invalid"
        DataOwnership.activateCloud(email: email)
        let scope = DataOwnership.activeScope
        defer {
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let baseline = Date(timeIntervalSince1970: 1700000000)
        let localAt = baseline.addingTimeInterval(60)
        let remoteAt = baseline.addingTimeInterval(120)
        let customer = Custumer(name: "Local customer", email: "", csource: "", type: 1, createdAt: baseline,
                                updateAt: localAt, syncBaseUpdatedAt: baseline)
        let trip = TripBookingRecord(form: NewTripFormModel())
        trip.createdAt = baseline;trip.updatedAt = localAt;trip.syncBaseUpdatedAt = baseline
        trip.memo = "Local memo";trip.price = 90;trip.isPaid = false;trip.isCompleted = false
        trip.locationStops = ["Local stop"]
        let localExpense = TripExpenseAdjustment(isAddition: true, title: "Local parking", amount: 12)
        let remoteExpense = TripExpenseAdjustment(isAddition: false, title: "Remote cost", amount: 20)
        trip.expenseAdjustments = [localExpense]
        if table == "customers" {
            context.insert(customer)
            context.insert(Connect(connectlable: "Phone", connecttype: "5550100", isDefault: true, customer: customer))
            context.insert(Address(addlable: "Home", addresses: "Local address", isDefault: true, customer: customer))
        } else { context.insert(trip) }
        try context.save()
        let id = table == "customers" ? customer.uuid : trip.id.uuidString.lowercased()
        let iso = ISO8601DateFormatter()
        var row: [String: Any] = ["id": id, "updated_at": iso.string(from: remoteAt),
                                 "created_at": iso.string(from: baseline),
                                 "deleted_at": remoteDeleted ? iso.string(from: remoteAt) as Any : NSNull()]
        if table == "customers" { row["name"] = "Remote customer" }
        else {
            row["memo"] = "Remote memo";row["price"] = 110
            row["is_paid"] = true;row["is_completed"] = true
        }
        let remoteChildren: [String: [[String: Any]]] = [
            "customer_contacts": [["customer_id": id, "contact_type": "Phone", "value": "5550199", "is_default": true]],
            "customer_addresses": [["customer_id": id, "label": "Home", "address": "Remote address", "is_default": true]],
            "trip_stops": [["trip_id": id, "position": 0, "address": "Remote stop"]],
            "trip_expenses": [["id": remoteExpense.id.uuidString.lowercased(), "trip_id": id, "position": 0,
                               "is_addition": remoteExpense.isAddition, "title": remoteExpense.title, "amount": remoteExpense.amount]]
        ]
        var postedParent = false
        SyncFixtureProtocol.handle = { fixture in
            let path = fixture.request.url!.path
            let endpoint = fixture.request.url!.lastPathComponent
            if path == "/auth/v1/user" {
                fixture.respond("{\"id\":\"00000000-0000-0000-0000-000000000001\"}");return
            }
            if fixture.request.httpMethod == "POST" && endpoint == table { postedParent = true }
            let payload: [[String: Any]]
            if fixture.request.httpMethod == "GET" && endpoint == table { payload = [row] }
            else if fixture.request.httpMethod == "GET" { payload = remoteChildren[endpoint] ?? [] }
            else { payload = [] }
            fixture.respond(String(decoding: try! JSONSerialization.data(withJSONObject: payload), as: UTF8.self))
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
        let conflicts = try context.fetch(FetchDescriptor<CloudSyncConflict>())
        XCTAssertEqual(conflicts.count, 1)
        let conflict = try XCTUnwrap(conflicts.first)
        XCTAssertEqual(conflict.tableName, table)
        XCTAssertEqual(conflict.recordID.lowercased(), id)
        XCTAssertEqual(conflict.isRemoteDeletion, remoteDeleted)
        XCTAssertFalse(postedParent, "An unresolved conflict must not upload the local version")
        if table == "customers" {
            XCTAssertEqual(customer.name, "Local customer")
            XCTAssertEqual(customer.connecttype.map(\.connecttype), ["5550100"])
            XCTAssertEqual(customer.addresses.map(\.addresses), ["Local address"])
        } else {
            XCTAssertEqual(trip.memo, "Local memo");XCTAssertEqual(trip.price, 90)
            XCTAssertFalse(trip.isPaid);XCTAssertFalse(trip.isCompleted)
            XCTAssertEqual(trip.locationStops, ["Local stop"])
            XCTAssertEqual(trip.expenseAdjustments, [localExpense])
        }
        if editingCustomer {
            SyncEditRegistry.begin(table: table, id: id, scope: scope)
            defer { SyncEditRegistry.end(table: table, id: id, scope: scope) }
            XCTAssertThrowsError(try SupabaseDataSync.resolveConflict(conflict, keepRemote: true, context: context))
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<Custumer>()), 1)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CloudSyncConflict>()), 1)
            return
        }
        if wrongScope {
            DataOwnership.activateCloud(email: "other-isolated-account@example.invalid")
            XCTAssertThrowsError(try SupabaseDataSync.resolveConflict(conflict, keepRemote: keepRemote, context: context))
            DataOwnership.activateCloud(email: email)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CloudSyncConflict>()), 1)
        }
        TripReminderScheduler.cancelledTripIDs = []
        try SupabaseDataSync.resolveConflict(conflict, keepRemote: keepRemote, context: context)
        XCTAssertEqual(TripReminderScheduler.cancelledTripIDs, table == "trips" && keepRemote && !remoteDeleted ? [trip.id] : [])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CloudSyncConflict>()), 0)
        postedParent = false
        if newerDeletion {
            let nextDeletionAt = remoteAt.addingTimeInterval(30)
            row["updated_at"] = iso.string(from: nextDeletionAt)
            row["deleted_at"] = iso.string(from: nextDeletionAt)
            _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
            let nextConflict = try XCTUnwrap(context.fetch(FetchDescriptor<CloudSyncConflict>()).first)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CloudSyncConflict>()), 1)
            XCTAssertEqual(nextConflict.remoteUpdatedAt, nextDeletionAt)
            XCTAssertTrue(nextConflict.isRemoteDeletion)
            XCTAssertFalse(postedParent)
            XCTAssertEqual(customer.name, "Local customer")
            XCTAssertEqual(customer.connecttype.map(\.connecttype), ["5550100"])
            XCTAssertEqual(customer.addresses.map(\.addresses), ["Local address"])
            return
        }
        _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CloudSyncConflict>()), 0)
        if remoteDeleted && keepRemote {
            XCTAssertFalse(postedParent)
            if table == "customers" { XCTAssertEqual(try context.fetchCount(FetchDescriptor<Custumer>()), 0) }
            else { XCTAssertEqual(try context.fetchCount(FetchDescriptor<TripBookingRecord>()), 0) }
            return
        }
        XCTAssertTrue(postedParent)
        let readback = ModelContext(container)
        if table == "customers" {
            let saved = try XCTUnwrap(readback.fetch(FetchDescriptor<Custumer>()).first)
            XCTAssertEqual(saved.name, keepRemote ? "Remote customer" : "Local customer")
            XCTAssertEqual(saved.connecttype.map(\.connecttype), [keepRemote ? "5550199" : "5550100"])
            XCTAssertEqual(saved.addresses.map(\.addresses), [keepRemote ? "Remote address" : "Local address"])
            if keepRemote { XCTAssertEqual(saved.syncBaseUpdatedAt, remoteAt) }
            else { XCTAssertGreaterThan(saved.updateAt, remoteAt) }
        } else {
            let saved = try XCTUnwrap(readback.fetch(FetchDescriptor<TripBookingRecord>()).first)
            XCTAssertEqual(saved.memo, keepRemote ? "Remote memo" : "Local memo")
            XCTAssertEqual(saved.price, keepRemote ? 110 : 90)
            XCTAssertEqual(saved.isPaid, keepRemote);XCTAssertEqual(saved.isCompleted, keepRemote)
            XCTAssertEqual(saved.locationStops, [keepRemote ? "Remote stop" : "Local stop"])
            XCTAssertEqual(saved.expenseAdjustments, [keepRemote ? remoteExpense : localExpense])
            if keepRemote { XCTAssertEqual(saved.syncBaseUpdatedAt, remoteAt) }
            else { XCTAssertGreaterThan(try XCTUnwrap(saved.updatedAt), remoteAt) }
        }
    }
    @MainActor func testCustomerConcurrentEditKeepLocal() async throws { try await runConflict(table: "customers", remoteDeleted: false, keepRemote: false) }
    @MainActor func testCustomerConcurrentEditKeepRemote() async throws { try await runConflict(table: "customers", remoteDeleted: false, keepRemote: true) }
    @MainActor func testTripConcurrentEditKeepLocal() async throws { try await runConflict(table: "trips", remoteDeleted: false, keepRemote: false) }
    @MainActor func testTripConcurrentEditKeepRemote() async throws { try await runConflict(table: "trips", remoteDeleted: false, keepRemote: true) }
    @MainActor func testCustomerRemoteDeleteRestoreLocal() async throws { try await runConflict(table: "customers", remoteDeleted: true, keepRemote: false) }
    @MainActor func testCustomerRemoteDeleteAccept() async throws { try await runConflict(table: "customers", remoteDeleted: true, keepRemote: true) }
    @MainActor func testTripRemoteDeleteRestoreLocal() async throws { try await runConflict(table: "trips", remoteDeleted: true, keepRemote: false) }
    @MainActor func testTripRemoteDeleteAccept() async throws { try await runConflict(table: "trips", remoteDeleted: true, keepRemote: true) }
    @MainActor func testCustomerRestorationStillDetectsNewerRemoteDeletion() async throws { try await runConflict(table: "customers", remoteDeleted: true, keepRemote: false, newerDeletion: true) }
    @MainActor func testOpenCustomerCannotAcceptRemoteDelete() async throws { try await runConflict(table: "customers", remoteDeleted: true, keepRemote: true, editingCustomer: true) }
    @MainActor func testOtherAccountCannotResolveCustomerConflict() async throws { try await runConflict(table: "customers", remoteDeleted: false, keepRemote: false, wrongScope: true) }
    @MainActor func testOtherAccountCannotResolveTripConflict() async throws { try await runConflict(table: "trips", remoteDeleted: false, keepRemote: false, wrongScope: true) }
}

final class LocalDeletionConflictAcceptanceTests: XCTestCase {
    @MainActor private func runDeletion(table: String, keepRemote: Bool, lostResponse: Bool = false, offlineBeforeCommit: Bool = false) async throws {
        let oldScope = DataOwnership.activeScope
        let email = "isolated-local-deletion@example.invalid"
        DataOwnership.activateCloud(email: email)
        defer {
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let baseline = Date(timeIntervalSince1970: 1700000000)
        // Future server time catches a deletion version that goes backwards.
        let remoteAt = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970) + 3600)
        let id: String
        switch table {
        case "customers":
            let item = Custumer(name: "Deleted local", email: "", csource: "", type: 1, createdAt: baseline, updateAt: baseline, syncBaseUpdatedAt: baseline)
            context.insert(item);id = item.uuid
            SupabaseDataSync.recordDeletion(table: table, id: id, context: context);context.delete(item)
        case "trips":
            let item = TripBookingRecord(form: NewTripFormModel())
            item.createdAt = baseline;item.updatedAt = baseline;item.syncBaseUpdatedAt = baseline
            context.insert(item);id = item.id.uuidString.lowercased()
            SupabaseDataSync.recordDeletion(table: table, id: id, context: context);context.delete(item)
        default:
            let item = TravelAgency(agencyCode: "QA", name: "Deleted local", createdAt: baseline, updateAt: baseline, syncBaseUpdatedAt: baseline)
            context.insert(item);id = item.uuid
            SupabaseDataSync.recordDeletion(table: table, id: id, context: context);context.delete(item)
        }
        try context.save()
        let tombstone = try XCTUnwrap(context.fetch(FetchDescriptor<CloudSyncDeletion>()).first)
        XCTAssertEqual(tombstone.baseUpdatedAt, baseline)
        let neighborID = UUID().uuidString.lowercased()
        let iso = ISO8601DateFormatter()
        let field = table == "trips" ? "memo" : "name"
        func row(_ rowID: String, _ value: String) -> [String: Any] {
            ["id": rowID, field: value, "updated_at": iso.string(from: remoteAt),
             "created_at": iso.string(from: baseline), "deleted_at": NSNull()]
        }
        var server: [String: [String: Any]] = [id: row(id, "Remote target"), neighborID: row(neighborID, "Untouched neighbor")]
        let expenseID = UUID().uuidString.lowercased()
        let children: [String: [[String: Any]]] = [
            "customer_contacts": [["customer_id": id, "contact_type": "Phone", "value": "5550199", "is_default": true]],
            "customer_addresses": [["customer_id": id, "label": "Home", "address": "Restored address", "is_default": true]],
            "trip_stops": [["trip_id": id, "position": 0, "address": "Restored stop"]],
            "trip_expenses": [["id": expenseID, "trip_id": id, "position": 0, "title": "Restored cost", "amount": 20, "is_addition": false]]
        ]
        var deletionVersions: [Date] = []
        var targetPosts = 0
        var injectedFailure = false
        func body(_ request: URLRequest) -> Data {
            if let data = request.httpBody { return data }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open();defer { stream.close() }
            var data = Data();var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break };data.append(contentsOf: buffer.prefix(count))
            }
            return data
        }
        SyncFixtureProtocol.handle = { fixture in
            let endpoint = fixture.request.url!.lastPathComponent
            let method = fixture.request.httpMethod ?? "GET"
            if fixture.request.url!.path == "/auth/v1/user" {
                fixture.respond("{\"id\":\"00000000-0000-0000-0000-000000000001\"}");return
            }
            if endpoint == table && method == "PATCH" {
                let query = URLComponents(url: fixture.request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                XCTAssertEqual(query.first(where: { $0.name == "id" })?.value, "eq.\(id)")
                let payload = (try? JSONSerialization.jsonObject(with: body(fixture.request))) as? [String: Any]
                let version = (payload?["updated_at"] as? String).flatMap(iso.date(from:))
                if let version { deletionVersions.append(version) }
                else { XCTFail("Deletion must carry a timestamp") }
                if offlineBeforeCommit && !injectedFailure {
                    injectedFailure = true;fixture.client?.urlProtocol(fixture, didFailWithError: URLError(.notConnectedToInternet));return
                }
                server[id]?["updated_at"] = payload?["updated_at"]
                server[id]?["deleted_at"] = payload?["deleted_at"]
                if lostResponse && !injectedFailure {
                    injectedFailure = true;fixture.client?.urlProtocol(fixture, didFailWithError: URLError(.networkConnectionLost));return
                }
                fixture.respond(fixture.request.value(forHTTPHeaderField: "Prefer") == "return=representation" ? "[{\"id\":\"\(id)\"}]" : "[]");return
            }
            if endpoint == table && method == "POST" {
                let rows = (try? JSONSerialization.jsonObject(with: body(fixture.request))) as? [[String: Any]] ?? []
                for row in rows {
                    if let key = row["id"] as? String {
                        if key == id { targetPosts += 1 };server[key] = row
                    }
                }
                fixture.respond("[]");return
            }
            let payload: [[String: Any]] = method == "GET"
                ? (endpoint == table ? Array(server.values) : children[endpoint] ?? []) : []
            fixture.respond(String(decoding: try! JSONSerialization.data(withJSONObject: payload), as: UTF8.self))
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
        let conflict = try XCTUnwrap(context.fetch(FetchDescriptor<CloudSyncConflict>()).first)
        XCTAssertTrue(conflict.isLocalDeletion);XCTAssertFalse(conflict.isRemoteDeletion)
        XCTAssertEqual(conflict.remoteUpdatedAt, remoteAt)
        XCTAssertTrue(deletionVersions.isEmpty);XCTAssertEqual(targetPosts, 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CloudSyncDeletion>()), 1)
        try SupabaseDataSync.resolveConflict(conflict, keepRemote: keepRemote, context: context)
        if lostResponse || offlineBeforeCommit {
            do {
                _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
                XCTFail("Expected injected deletion network failure")
            } catch { XCTAssertTrue(injectedFailure) }
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<CloudSyncDeletion>()), 1, "Failed deletion must remain queued")
        }
        _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CloudSyncConflict>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CloudSyncDeletion>()), 0)
        XCTAssertEqual(server[neighborID]?[field] as? String, "Untouched neighbor")
        XCTAssertTrue(server[neighborID]?["deleted_at"] is NSNull)
        if !keepRemote {
            XCTAssertFalse(deletionVersions.isEmpty)
            for version in deletionVersions { XCTAssertGreaterThan(version, remoteAt, "Confirmed deletion must be newer than the resolved remote edit") }
            XCTAssertEqual(targetPosts, 0)
            XCTAssertNotNil(server[id]?["deleted_at"] as? String)
        } else {
            XCTAssertTrue(deletionVersions.isEmpty)
            XCTAssertGreaterThan(targetPosts, 0)
            XCTAssertTrue(server[id]?["deleted_at"] is NSNull)
        }
        let readback = ModelContext(container)
        switch table {
        case "customers":
            let records = try readback.fetch(FetchDescriptor<Custumer>())
            XCTAssertEqual(records.count, keepRemote ? 2 : 1)
            if keepRemote {
                let target = try XCTUnwrap(records.first { $0.uuid == id })
                XCTAssertEqual(target.name, "Remote target")
                XCTAssertEqual(target.connecttype.map(\.connecttype), ["5550199"])
                XCTAssertEqual(target.addresses.map(\.addresses), ["Restored address"])
            }
        case "trips":
            let records = try readback.fetch(FetchDescriptor<TripBookingRecord>())
            XCTAssertEqual(records.count, keepRemote ? 2 : 1)
            if keepRemote {
                let target = try XCTUnwrap(records.first { $0.id.uuidString.lowercased() == id })
                XCTAssertEqual(target.memo, "Remote target")
                XCTAssertEqual(target.locationStops, ["Restored stop"])
                XCTAssertEqual(target.expenseAdjustments.map { $0.id.uuidString.lowercased() }, [expenseID])
            }
        default:
            let records = try readback.fetch(FetchDescriptor<TravelAgency>())
            XCTAssertEqual(records.count, keepRemote ? 2 : 1)
            if keepRemote { XCTAssertEqual(records.first { $0.uuid == id }?.name, "Remote target") }
        }
    }
    @MainActor func testDeletedCustomerRestoreCloudIncludingChildren() async throws { try await runDeletion(table: "customers", keepRemote: true) }
    @MainActor func testDeletedTripRestoreCloudIncludingChildren() async throws { try await runDeletion(table: "trips", keepRemote: true) }
    @MainActor func testDeletedAgencyRestoreCloud() async throws { try await runDeletion(table: "travel_agencies", keepRemote: true) }
    @MainActor func testConfirmCustomerDeletionAfterFutureRemoteEdit() async throws { try await runDeletion(table: "customers", keepRemote: false) }
    @MainActor func testConfirmTripDeletionAfterFutureRemoteEdit() async throws { try await runDeletion(table: "trips", keepRemote: false) }
    @MainActor func testConfirmAgencyDeletionAfterFutureRemoteEdit() async throws { try await runDeletion(table: "travel_agencies", keepRemote: false) }
    @MainActor func testDeletionLostResponseRetainsQueueAndRetryConverges() async throws { try await runDeletion(table: "trips", keepRemote: false, lostResponse: true) }
    @MainActor func testDeletionOfflineBeforeCommitRetainsQueueAndRetryConverges() async throws { try await runDeletion(table: "customers", keepRemote: false, offlineBeforeCommit: true) }
}

final class DeletionCompareAndSetTests: XCTestCase {
    @MainActor private func runRace(table: String, mode: String) async throws {
        let oldScope = DataOwnership.activeScope
        let email = "isolated-deletion-cas@example.invalid"
        DataOwnership.activateCloud(email: email)
        defer {
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let owner = "00000000-0000-0000-0000-000000000001"
        let id = UUID().uuidString.lowercased()
        let baseline = mode == "future-version"
            ? Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970) + 3600)
            : Date(timeIntervalSince1970: 1700000000)
        let changedAt = baseline.addingTimeInterval(60)
        let deletedAt = mode == "future-version" ? Date.now : baseline.addingTimeInterval(120)
        let iso = ISO8601DateFormatter()
        let field = table == "trips" ? "memo" : "name"
        let versionText = mode == "offset-version" ? "2023-11-14T22:13:20.000+00:00" : iso.string(from: baseline)
        var server: [String: Any]? = ["id": id, "owner_id": owner, field: "Original remote",
                                    "created_at": iso.string(from: baseline), "updated_at": versionText,
                                    "deleted_at": NSNull()]
        if mode == "missing" { server = nil }
        if mode == "already-deleted" {
            server?["updated_at"] = iso.string(from: changedAt)
            server?["deleted_at"] = iso.string(from: changedAt)
        }
        if mode == "invalid-version" { server?["updated_at"] = "invalid-date" }
        context.insert(CloudSyncDeletion(tableName: table, recordID: id, deletedAt: deletedAt, baseUpdatedAt: baseline))
        try context.save()
        var patchCount = 0
        var targetPosts = 0
        var injected = false
        func body(_ request: URLRequest) -> Data {
            if let data = request.httpBody { return data }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open();defer { stream.close() }
            var data = Data();var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break };data.append(contentsOf: buffer.prefix(count))
            }
            return data
        }
        SyncFixtureProtocol.handle = { fixture in
            let endpoint = fixture.request.url!.lastPathComponent
            let method = fixture.request.httpMethod ?? "GET"
            if fixture.request.url!.path == "/auth/v1/user" {
                fixture.respond("{\"id\":\"\(owner)\"}");return
            }
            if endpoint == table && method == "PATCH" {
                patchCount += 1
                let query = URLComponents(url: fixture.request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
                let filters = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
                XCTAssertEqual(filters["id"], "eq.\(id)")
                XCTAssertEqual(filters["owner_id"], "eq.\(owner)")
                XCTAssertEqual(filters["deleted_at"], "is.null")
                XCTAssertEqual(filters["updated_at"], "eq.\"\(versionText)\"")
                if mode == "offset-version" {
                    XCTAssertTrue(fixture.request.url!.absoluteString.contains("%2B"), "Literal timezone plus must be percent encoded")
                }
                XCTAssertEqual(fixture.request.value(forHTTPHeaderField: "Prefer"), "return=representation")
                if mode == "server-failure" { fixture.respond("{\"message\":\"Fixture unavailable\"}", status: 503);return }
                if mode == "malformed-response" { fixture.respond("{}");return }
                if mode == "wrong-id-response" { fixture.respond("[{\"id\":\"00000000-0000-0000-0000-000000000099\"}]");return }
                if !injected && (mode == "remote-edit" || mode == "remote-delete") {
                    injected = true
                    server?[field] = "Concurrent remote edit"
                    server?["updated_at"] = iso.string(from: changedAt)
                    if mode == "remote-delete" { server?["deleted_at"] = iso.string(from: changedAt) }
                }
                // Model server-side conditional matching, including legacy unconditional writes.
                let versionMatches = filters["updated_at"].map { $0 == "eq.\"\(server?["updated_at"] as? String ?? "")\"" } ?? true
                let deletionMatches = filters["deleted_at"] == nil || server?["deleted_at"] is NSNull
                if server != nil && versionMatches && deletionMatches {
                    let payload = (try? JSONSerialization.jsonObject(with: body(fixture.request))) as? [String: Any]
                    server?["updated_at"] = payload?["updated_at"]
                    server?["deleted_at"] = payload?["deleted_at"]
                    fixture.respond(fixture.request.value(forHTTPHeaderField: "Prefer") == "return=representation" ? "[{\"id\":\"\(id)\"}]" : "[]")
                } else { fixture.respond("[]") }
                return
            }
            if endpoint == table && method == "POST" { targetPosts += 1 }
            let payload: [[String: Any]] = endpoint == table && method == "GET" ? server.map { [$0] } ?? [] : []
            fixture.respond(String(decoding: try! JSONSerialization.data(withJSONObject: payload), as: UTF8.self))
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        let shouldThrow = mode == "server-failure" || mode == "malformed-response" || mode == "wrong-id-response" || mode == "invalid-version"
        do {
            _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
            XCTAssertFalse(shouldThrow)
        } catch { XCTAssertTrue(shouldThrow, "Unexpected error: \(error)") }
        let conflicts = try context.fetch(FetchDescriptor<CloudSyncConflict>())
        let tombstones = try context.fetch(FetchDescriptor<CloudSyncDeletion>())
        XCTAssertEqual(targetPosts, 0, "Pending or completed local deletion must not re-upload a stale target")
        if mode == "remote-edit" {
            XCTAssertTrue(injected)
            XCTAssertEqual(patchCount, 1)
            XCTAssertEqual(server?[field] as? String, "Concurrent remote edit")
            XCTAssertTrue(server?["deleted_at"] is NSNull, "A new remote edit must not be deleted")
            XCTAssertEqual(tombstones.count, 1)
            let conflict = try XCTUnwrap(conflicts.first)
            XCTAssertEqual(conflicts.count, 1)
            XCTAssertTrue(conflict.isLocalDeletion)
            XCTAssertEqual(conflict.remoteUpdatedAt, changedAt)
            let payload = try JSONSerialization.jsonObject(with: Data(conflict.remotePayloadJSON.utf8)) as? [String: Any]
            XCTAssertEqual(payload?[field] as? String, "Concurrent remote edit")
        } else if shouldThrow {
            if mode == "invalid-version" { XCTAssertEqual(patchCount, 0) }
            XCTAssertEqual(tombstones.count, 1)
            XCTAssertTrue(conflicts.isEmpty)
            XCTAssertTrue(server?["deleted_at"] is NSNull)
        } else {
            XCTAssertTrue(tombstones.isEmpty)
            XCTAssertTrue(conflicts.isEmpty)
            if mode == "missing" || mode == "already-deleted" { XCTAssertEqual(patchCount, 0) }
            if mode == "remote-delete" || mode == "already-deleted" {
                XCTAssertEqual(server?["updated_at"] as? String, iso.string(from: changedAt), "An already completed remote deletion must not be rewritten")
            }
            if mode == "normal" || mode == "offset-version" {
                XCTAssertEqual(patchCount, 1)
                XCTAssertEqual(server?["deleted_at"] as? String, iso.string(from: deletedAt))
            }
            if mode == "future-version" {
                XCTAssertEqual(patchCount, 1)
                let version = try XCTUnwrap((server?["deleted_at"] as? String).flatMap(iso.date(from:)))
                XCTAssertGreaterThan(version, baseline)
            }
        }
    }
    @MainActor func testCustomerChangedAfterReadCannotBeDeleted() async throws { try await runRace(table: "customers", mode: "remote-edit") }
    @MainActor func testTripChangedAfterReadCannotBeDeleted() async throws { try await runRace(table: "trips", mode: "remote-edit") }
    @MainActor func testAgencyChangedAfterReadCannotBeDeleted() async throws { try await runRace(table: "travel_agencies", mode: "remote-edit") }
    @MainActor func testUnchangedCustomerConditionalDeleteSucceeds() async throws { try await runRace(table: "customers", mode: "normal") }
    @MainActor func testUnchangedTripConditionalDeleteSucceeds() async throws { try await runRace(table: "trips", mode: "normal") }
    @MainActor func testUnchangedAgencyConditionalDeleteSucceeds() async throws { try await runRace(table: "travel_agencies", mode: "normal") }
    @MainActor func testMissingRemoteDoesNotIssueDeletePatch() async throws { try await runRace(table: "trips", mode: "missing") }
    @MainActor func testAlreadyDeletedRemoteDoesNotIssueDeletePatch() async throws { try await runRace(table: "customers", mode: "already-deleted") }
    @MainActor func testRemoteDeletionDuringPatchIsAcknowledgedWithoutRewrite() async throws { try await runRace(table: "trips", mode: "remote-delete") }
    @MainActor func testDeleteServerFailureKeepsQueue() async throws { try await runRace(table: "customers", mode: "server-failure") }
    @MainActor func testFractionalTimestampWithTimezoneMatchesExactRemoteVersion() async throws { try await runRace(table: "trips", mode: "offset-version") }
    @MainActor func testUnchangedFutureRemoteBaselineStillGetsNewerDeletionVersion() async throws { try await runRace(table: "customers", mode: "future-version") }
    @MainActor func testWrongRecordAcknowledgementCannotClearQueue() async throws { try await runRace(table: "customers", mode: "wrong-id-response") }
    @MainActor func testInvalidRemoteVersionNeverStartsDeletion() async throws { try await runRace(table: "trips", mode: "invalid-version") }
    @MainActor func testMalformedDeleteResponseCannotClearQueue() async throws { try await runRace(table: "trips", mode: "malformed-response") }
}

final class DeletionAccountSwitchTests: XCTestCase {
    @MainActor private func runSwitch(table: String, stage: String) async throws {
        let oldScope = DataOwnership.activeScope
        let email = "isolated-delete-old@example.invalid"
        let otherEmail = "isolated-delete-new@example.invalid"
        DataOwnership.activateCloud(email: email)
        let scope = DataOwnership.activeScope
        defer {
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let id = UUID().uuidString.lowercased()
        let otherID = UUID().uuidString.lowercased()
        let baseline = Date(timeIntervalSince1970: 1700000000)
        let iso = ISO8601DateFormatter()
        context.insert(CloudSyncDeletion(tableName: table, recordID: id, baseUpdatedAt: baseline))
        DataOwnership.activateCloud(email: otherEmail)
        let otherScope = DataOwnership.activeScope
        context.insert(CloudSyncDeletion(tableName: table, recordID: otherID, baseUpdatedAt: baseline))
        let otherCustomer = Custumer(name: "Untouched new account", email: "", csource: "", type: 1)
        context.insert(otherCustomer)
        try context.save()
        DataOwnership.activateCloud(email: email)
        var server: [String: Any] = ["id": id, "name": "Old account", "memo": "Old account",
                                   "created_at": iso.string(from: baseline), "updated_at": iso.string(from: baseline), "deleted_at": NSNull()]
        var injected = false
        var monitor = true
        var requestsAfterSwitch = 0
        var parentReads = 0
        var patches = 0
        func switchAndRespond(_ fixture: SyncFixtureProtocol, _ payload: String) {
            Task { @MainActor in
                injected = true
                DataOwnership.activateCloud(email: otherEmail)
                fixture.respond(payload)
            }
        }
        SyncFixtureProtocol.handle = { fixture in
            if injected && monitor { requestsAfterSwitch += 1 }
            let path = fixture.request.url!.path
            let endpoint = fixture.request.url!.lastPathComponent
            let method = fixture.request.httpMethod ?? "GET"
            if path == "/auth/v1/user" {
                let payload = "{\"id\":\"00000000-0000-0000-0000-000000000001\"}"
                if stage == "auth" && !injected { switchAndRespond(fixture, payload) }
                else { fixture.respond(payload) }
                return
            }
            if endpoint == table && method == "GET" {
                parentReads += 1
                let payload = stage == "missing" ? "[]" : String(decoding: try! JSONSerialization.data(withJSONObject: [server]), as: UTF8.self)
                if !injected && (stage == "preflight" || stage == "missing" || (stage == "refetch" && parentReads == 2)) {
                    switchAndRespond(fixture, payload)
                } else { fixture.respond(payload) }
                return
            }
            if endpoint == table && method == "PATCH" {
                patches += 1
                if stage == "refetch" && !injected {
                    server["updated_at"] = iso.string(from: baseline.addingTimeInterval(60))
                    fixture.respond("[]");return
                }
                server["updated_at"] = iso.string(from: baseline.addingTimeInterval(120))
                server["deleted_at"] = iso.string(from: baseline.addingTimeInterval(120))
                let payload = "[{\"id\":\"\(id)\"}]"
                if stage == "patch" && !injected { switchAndRespond(fixture, payload) }
                else { fixture.respond(payload) }
                return
            }
            fixture.respond("[]")
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        do {
            _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
            XCTFail("Old account sync must stop on account change")
        } catch {
            XCTAssertEqual(error.localizedDescription, SupabaseDataSync.SyncError.accountChanged.localizedDescription)
        }
        XCTAssertTrue(injected)
        XCTAssertEqual(requestsAfterSwitch, 0, "No follow-up old-account request is allowed after observing account change")
        XCTAssertEqual(patches, stage == "patch" || stage == "refetch" ? 1 : 0)
        var pending = try context.fetch(FetchDescriptor<CloudSyncDeletion>())
        XCTAssertEqual(pending.filter { $0.ownerScope == scope }.map(\.recordID), [id])
        XCTAssertEqual(pending.filter { $0.ownerScope == otherScope }.map(\.recordID), [otherID])
        XCTAssertTrue(try context.fetch(FetchDescriptor<CloudSyncConflict>()).isEmpty)
        XCTAssertEqual(otherCustomer.name, "Untouched new account")
        XCTAssertNil(otherCustomer.syncBaseUpdatedAt)
        // Switching back may acknowledge a committed deletion or surface the new
        // remote edit, while the new account's pending deletion stays untouched.
        monitor = false
        DataOwnership.activateCloud(email: email)
        _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
        pending = try context.fetch(FetchDescriptor<CloudSyncDeletion>())
        XCTAssertEqual(pending.filter { $0.ownerScope == otherScope }.map(\.recordID), [otherID])
        XCTAssertEqual(pending.filter { $0.ownerScope == scope }.count, stage == "refetch" ? 1 : 0)
        let conflicts = try context.fetch(FetchDescriptor<CloudSyncConflict>())
        XCTAssertEqual(conflicts.count, stage == "refetch" ? 1 : 0)
        XCTAssertTrue(conflicts.allSatisfy { $0.ownerScope == scope })
        XCTAssertEqual(otherCustomer.name, "Untouched new account")
        XCTAssertNil(otherCustomer.syncBaseUpdatedAt)
    }
    @MainActor func testAccountSwitchDuringAuthenticationStopsDeletion() async throws { try await runSwitch(table: "customers", stage: "auth") }
    @MainActor func testAccountSwitchAfterDeletionPreflightStopsPatch() async throws { try await runSwitch(table: "customers", stage: "preflight") }
    @MainActor func testAccountSwitchAfterMissingRowDoesNotClearQueue() async throws { try await runSwitch(table: "trips", stage: "missing") }
    @MainActor func testAccountSwitchAfterDeletionCommitRetainsAcknowledgementWork() async throws { try await runSwitch(table: "trips", stage: "patch") }
    @MainActor func testAccountSwitchDuringConflictRefetchDoesNotPublishStaleConflict() async throws { try await runSwitch(table: "travel_agencies", stage: "refetch") }
}

final class EntityUploadAccountSwitchTests: XCTestCase {
    @MainActor private func runSwitch(at phase: String) async throws {
        let oldScope = DataOwnership.activeScope
        let email = "isolated-entity-old@example.invalid"
        let otherEmail = "isolated-entity-new@example.invalid"
        DataOwnership.activateCloud(email: email)
        defer {
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        let sentAt = Date(timeIntervalSince1970: 1700000000)
        let agency = TravelAgency(agencyCode: "QA", name: "Old agency", createdAt: sentAt, updateAt: sentAt)
        let customer = Custumer(name: "Old customer", email: "", csource: "", type: 1, createdAt: sentAt, updateAt: sentAt)
        let secondCustomer = Custumer(name: "Second old customer", email: "", csource: "", type: 1, createdAt: sentAt, updateAt: sentAt)
        let trip = TripBookingRecord(form: NewTripFormModel())
        let secondTrip = TripBookingRecord(form: NewTripFormModel())
        for item in [trip, secondTrip] { item.createdAt = sentAt;item.updatedAt = sentAt;context.insert(item) }
        trip.memo = "Old memo";trip.locationStops = ["Old stop"]
        let expense = TripExpenseAdjustment(isAddition: true, title: "Parking", amount: 12)
        trip.expenseAdjustments = [expense]
        context.insert(agency);context.insert(customer);context.insert(secondCustomer)
        context.insert(Connect(connectlable: "Phone", connecttype: "5550100", isDefault: true, customer: customer))
        context.insert(Address(addlable: "Home", addresses: "Old address", isDefault: true, customer: customer))
        DataOwnership.activateCloud(email: otherEmail)
        let otherCustomer = Custumer(name: "New account untouched", email: "", csource: "", type: 1)
        context.insert(otherCustomer)
        try context.save()
        DataOwnership.activateCloud(email: email)
        let otherCustomerID = otherCustomer.uuid
        var server: [String: [String: [String: Any]]] = [:]
        var injected = false
        var monitor = true
        var requestsAfterSwitch = 0
        func body(_ request: URLRequest) -> Data {
            if let data = request.httpBody { return data }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open();defer { stream.close() }
            var data = Data();var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break };data.append(contentsOf: buffer.prefix(count))
            }
            return data
        }
        SyncFixtureProtocol.handle = { fixture in
            if monitor && injected { requestsAfterSwitch += 1 }
            let table = fixture.request.url!.lastPathComponent
            let method = fixture.request.httpMethod ?? "GET"
            if fixture.request.url!.path == "/auth/v1/user" {
                fixture.respond("{\"id\":\"00000000-0000-0000-000000000001\"}");return
            }
            if method == "POST", let posted = (try? JSONSerialization.jsonObject(with: body(fixture.request))) as? [[String: Any]] {
                for row in posted {
                    if let id = row["id"] as? String {
                        XCTAssertNotEqual(id, otherCustomerID, "The new account must never enter an old-account request")
                        server[table, default: [:]][id] = row
                    }
                }
            }
            if method == "PATCH" {
                let query = URLComponents(url: fixture.request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
                for parent in ["customer_id", "trip_id"] {
                    if let filter = query.first(where: { $0.name == parent })?.value {
                        let id = String(filter.dropFirst(3))
                        for key in Array(server[table, default: [:]].keys) where server[table]?[key]?[parent] as? String == id {
                            server[table]?[key]?["deleted_at"] = "2026-10-25T00:00:00Z"
                        }
                    }
                }
            }
            let rows = method == "GET" ? Array(server[table, default: [:]].values) : []
            let payload = String(decoding: try! JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
            if !injected && "\(method) \(table)" == phase {
                Task { @MainActor in
                    injected = true
                    DataOwnership.activateCloud(email: otherEmail)
                    fixture.respond(payload)
                }
            } else { fixture.respond(payload) }
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        do {
            _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
            XCTFail("Expected old-account upload to stop")
        } catch { XCTAssertEqual(error.localizedDescription, SupabaseDataSync.SyncError.accountChanged.localizedDescription) }
        XCTAssertTrue(injected)
        XCTAssertEqual(requestsAfterSwitch, 0, "Do not continue any old-account request after switching")
        XCTAssertNil(agency.syncBaseUpdatedAt)
        for item in [customer, secondCustomer, otherCustomer] { XCTAssertNil(item.syncBaseUpdatedAt) }
        for item in [trip, secondTrip] { XCTAssertNil(item.syncBaseUpdatedAt) }
        XCTAssertEqual(customer.connecttype.map(\.connecttype), ["5550100"])
        XCTAssertEqual(customer.addresses.map(\.addresses), ["Old address"])
        XCTAssertEqual(trip.memo, "Old memo")
        XCTAssertEqual(trip.locationStops, ["Old stop"])
        XCTAssertEqual(trip.expenseAdjustments, [expense])
        XCTAssertEqual(otherCustomer.name, "New account untouched")
        monitor = false
        DataOwnership.activateCloud(email: email)
        _ = try await SupabaseDataSync.uploadLocalData(context: context, accessToken: "fixture-only", accountEmail: email)
        XCTAssertEqual(agency.syncBaseUpdatedAt, sentAt)
        for item in [customer, secondCustomer] { XCTAssertEqual(item.syncBaseUpdatedAt, sentAt) }
        for item in [trip, secondTrip] { XCTAssertEqual(item.syncBaseUpdatedAt, sentAt) }
        XCTAssertNil(otherCustomer.syncBaseUpdatedAt)
        XCTAssertEqual(otherCustomer.name, "New account untouched")
        XCTAssertFalse(server["customers", default: [:]].keys.contains(otherCustomer.uuid))
        for (table, count) in ["travel_agencies": 1, "customers": 2, "trips": 2, "customer_contacts": 1, "customer_addresses": 1, "trip_stops": 1, "trip_expenses": 1] {
            XCTAssertEqual(server[table, default: [:]].values.filter { $0["deleted_at"] is NSNull }.count, count)
        }
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TripBookingRecord>()).first { $0.id == trip.id })
        XCTAssertEqual(saved.locationStops, ["Old stop"])
        XCTAssertEqual(saved.expenseAdjustments, [expense])
        XCTAssertTrue(try context.fetch(FetchDescriptor<CloudSyncConflict>()).isEmpty)
    }
    @MainActor func testSwitchDuringAgencyPullStopsFurtherReads() async throws { try await runSwitch(at: "GET travel_agencies") }
    @MainActor func testSwitchDuringTripPullStopsUpload() async throws { try await runSwitch(at: "GET trips") }
    @MainActor func testSwitchDuringAgencyUploadStopsCustomerUpload() async throws { try await runSwitch(at: "POST travel_agencies") }
    @MainActor func testSwitchDuringCustomerUploadStopsChildReplacement() async throws { try await runSwitch(at: "POST customers") }
    @MainActor func testSwitchDuringContactReplacementStopsNextCustomer() async throws { try await runSwitch(at: "PATCH customer_contacts") }
    @MainActor func testSwitchDuringAddressReplacementStopsNextCustomer() async throws { try await runSwitch(at: "PATCH customer_addresses") }
    @MainActor func testSwitchDuringContactUploadStopsAddressUpload() async throws { try await runSwitch(at: "POST customer_contacts") }
    @MainActor func testSwitchDuringAddressUploadStopsTripUpload() async throws { try await runSwitch(at: "POST customer_addresses") }
    @MainActor func testSwitchDuringTripUploadStopsChildReplacement() async throws { try await runSwitch(at: "POST trips") }
    @MainActor func testSwitchDuringStopReplacementStopsNextTrip() async throws { try await runSwitch(at: "PATCH trip_stops") }
    @MainActor func testSwitchDuringExpenseReplacementStopsNextTrip() async throws { try await runSwitch(at: "PATCH trip_expenses") }
    @MainActor func testSwitchDuringStopUploadStopsExpenses() async throws { try await runSwitch(at: "POST trip_stops") }
    @MainActor func testSwitchDuringExpenseUploadDoesNotAcknowledgeBaseline() async throws { try await runSwitch(at: "POST trip_expenses") }
}

final class AccountImageTransferSwitchTests: XCTestCase {
    @MainActor private func runTransfer(payment: Bool, downloading: Bool, stage: String) async throws {
        let oldScope = DataOwnership.activeScope
        let tag = UUID().uuidString.lowercased()
        let email = "isolated-assets-old-\(tag)@example.invalid"
        let otherEmail = "isolated-assets-new-\(tag)@example.invalid"
        let asset: AccountAssetStore.Asset = payment ? .paymentMethods : .businessCard
        let baseAt = Date(timeIntervalSince1970: 1700000000)
        let remoteAt = baseAt.addingTimeInterval(60)
        let owner = "00000000-0000-0000-0000-000000000001"
        let png = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { renderer in
            renderer.cgContext.setFillColor(UIColor.red.cgColor)
            renderer.cgContext.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        let marker = Data("{\"fixture\":\"Untouched namespace\"}".utf8)
        let localObject: [String: Any] = payment
            ? ["methods": [["id": "pay-a", "qrImageData": png.base64EncodedString()], ["id": "pay-b", "qrImageData": png.base64EncodedString()]]]
            : ["portraitData": png.base64EncodedString(), "qrCodes": [["id": "qr-a", "imageData": png.base64EncodedString()], ["id": "qr-b", "imageData": png.base64EncodedString()]]]
        let remoteObject: [String: Any] = payment
            ? ["methods": [["id": "pay-a", "qrImagePath": "\(owner)/payment-methods/pay-a.jpg"], ["id": "pay-b", "qrImagePath": "\(owner)/payment-methods/pay-b.jpg"]]]
            : ["portraitPath": "\(owner)/business-card/portrait.jpg", "qrCodes": [["id": "qr-a", "imagePath": "\(owner)/business-card/qr/qr-a.jpg"], ["id": "qr-b", "imagePath": "\(owner)/business-card/qr/qr-b.jpg"]]]
        let localData = downloading ? Data("{\"fixture\":\"Old local\"}".utf8) : try JSONSerialization.data(withJSONObject: localObject, options: [.sortedKeys])
        AccountAssetStore.set(localData, for: asset, email: email, namespace: .cloud, updatedAt: baseAt)
        AccountAssetStore.set(marker, for: asset, email: email, namespace: .local, updatedAt: baseAt)
        AccountAssetStore.set(marker, for: asset, email: otherEmail, namespace: .cloud, updatedAt: baseAt)
        DataOwnership.activateCloud(email: email)
        defer {
            for account in [email, otherEmail] {
                for item in AccountAssetStore.Asset.allCases {
                    AccountAssetStore.set(nil, for: item, email: account, namespace: .cloud)
                    AccountAssetStore.set(nil, for: item, email: account, namespace: .local)
                }
            }
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        var remoteSettings: [String: Any]? = downloading ? [asset.cloudColumn: remoteObject, "\(asset.cloudColumn)_updated_at": ISO8601DateFormatter().string(from: remoteAt)] : nil
        var objects: [String: Data] = [:]
        var images = 0
        var settingsWrites = 0
        var injected = false
        var monitor = true
        var requestsAfterSwitch = 0
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(forName: .accountAssetsDidSync, object: nil, queue: .main) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        func body(_ request: URLRequest) -> Data {
            if let data = request.httpBody { return data }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open();defer { stream.close() }
            var data = Data();var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break };data.append(contentsOf: buffer.prefix(count))
            }
            return data
        }
        func send(_ fixture: SyncFixtureProtocol, _ payload: String, image: Bool) {
            if image {
                fixture.client?.urlProtocol(fixture, didReceive: HTTPURLResponse(url: fixture.request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!, cacheStoragePolicy: .notAllowed)
                fixture.client?.urlProtocol(fixture, didLoad: png)
                fixture.client?.urlProtocolDidFinishLoading(fixture)
            } else { fixture.respond(payload) }
        }
        SyncFixtureProtocol.handle = { fixture in
            if monitor && injected { requestsAfterSwitch += 1 }
            let path = fixture.request.url!.path
            let method = fixture.request.httpMethod ?? "GET"
            if path == "/auth/v1/user" {
                fixture.respond("{\"id\":\"\(owner)\"}");return
            }
            var phase = ""
            var imageResponse = false
            var payload = "{}"
            if path == "/rest/v1/user_settings" {
                if method == "GET" {
                    phase = "settings-read"
                    payload = String(decoding: try! JSONSerialization.data(withJSONObject: remoteSettings.map { [$0] } ?? []), as: UTF8.self)
                } else {
                    phase = "settings-write";settingsWrites += 1
                    remoteSettings = (try? JSONSerialization.jsonObject(with: body(fixture.request))) as? [String: Any]
                }
            } else if path.contains("/account-assets/") {
                images += 1;phase = "image-\(images)"
                let key = path.components(separatedBy: "/account-assets/").last!
                XCTAssertTrue(key.hasPrefix(owner + "/"))
                if method == "POST" {
                    XCTAssertEqual(fixture.request.value(forHTTPHeaderField: "x-upsert"), "true")
                    let data = body(fixture.request)
                    XCTAssertNotNil(UIImage(data: data))
                    objects[key] = data
                } else { imageResponse = true }
            } else { XCTFail("Unexpected fixture request: \(path)") }
            if stage != "none" && !injected && phase == stage {
                Task { @MainActor in
                    injected = true
                    DataOwnership.activateCloud(email: otherEmail)
                    send(fixture, payload, image: imageResponse)
                }
            } else { send(fixture, payload, image: imageResponse) }
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        do {
            try await SupabaseDataSync.syncAccountAssets(email: email, accessToken: "fixture-only")
            XCTAssertEqual(stage, "none", "Interrupted asset sync must report account change")
        } catch {
            XCTAssertNotEqual(stage, "none")
            XCTAssertEqual(error.localizedDescription, SupabaseDataSync.SyncError.accountChanged.localizedDescription)
        }
        if stage != "none" {
            XCTAssertTrue(injected)
            XCTAssertEqual(requestsAfterSwitch, 0)
            XCTAssertEqual(notifications, 0)
            XCTAssertEqual(AccountAssetStore.data(for: asset, email: email, namespace: .cloud), localData, "Do not replace the old account's stored draft after switching")
            XCTAssertEqual(AccountAssetStore.updatedAt(for: asset, email: email, namespace: .cloud), baseAt)
            monitor = false
            DataOwnership.activateCloud(email: email)
            try await SupabaseDataSync.syncAccountAssets(email: email, accessToken: "fixture-only")
        }
        XCTAssertEqual(AccountAssetStore.data(for: asset, email: otherEmail, namespace: .cloud), marker)
        XCTAssertEqual(AccountAssetStore.data(for: asset, email: email, namespace: .local), marker)
        let saved = try XCTUnwrap(AccountAssetStore.data(for: asset, email: email, namespace: .cloud))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        if downloading {
            XCTAssertEqual(settingsWrites, 0)
            XCTAssertEqual(notifications, 1)
            XCTAssertEqual(AccountAssetStore.updatedAt(for: asset, email: email, namespace: .cloud), remoteAt)
            let imageText = payment ? (json["methods"] as? [[String: Any]])?.first?["qrImageData"] as? String : json["portraitData"] as? String
            XCTAssertNotNil(imageText.flatMap { Data(base64Encoded: $0) }.flatMap { UIImage(data: $0) })
        } else {
            XCTAssertEqual(saved, localData, "Successful image upload retains local image bytes for offline use")
            XCTAssertEqual(objects.count, payment ? 1 : 2, "Identical QR bytes share one immutable content object within their category")
            let remote = try XCTUnwrap(remoteSettings?[asset.cloudColumn] as? [String: Any])
            if payment {
                let methods = try XCTUnwrap(remote["methods"] as? [[String: Any]])
                XCTAssertTrue(methods.allSatisfy { $0["qrImageData"] == nil && $0["qrImagePath"] != nil })
            } else {
                XCTAssertNil(remote["portraitData"]);XCTAssertNotNil(remote["portraitPath"])
                let codes = try XCTUnwrap(remote["qrCodes"] as? [[String: Any]])
                XCTAssertTrue(codes.allSatisfy { $0["imageData"] == nil && $0["imagePath"] != nil })
            }
        }
    }
    @MainActor func testSwitchDuringAssetSettingsReadStopsUploads() async throws { try await runTransfer(payment: false, downloading: false, stage: "settings-read") }
    @MainActor func testSwitchDuringPortraitUploadStopsQRCodes() async throws { try await runTransfer(payment: false, downloading: false, stage: "image-1") }
    @MainActor func testSwitchDuringCardQRUploadStopsNextImage() async throws { try await runTransfer(payment: false, downloading: false, stage: "image-2") }
    @MainActor func testSwitchDuringPaymentQRUploadStopsNextMethod() async throws { try await runTransfer(payment: true, downloading: false, stage: "image-1") }
    @MainActor func testSwitchAfterAssetSettingsCommitReportsAccountChange() async throws { try await runTransfer(payment: false, downloading: false, stage: "settings-write") }
    @MainActor func testSwitchDuringAssetSettingsReadStopsDownloads() async throws { try await runTransfer(payment: false, downloading: true, stage: "settings-read") }
    @MainActor func testSwitchDuringPortraitDownloadPreservesStoredDraft() async throws { try await runTransfer(payment: false, downloading: true, stage: "image-1") }
    @MainActor func testSwitchDuringCardQRDownloadStopsNextImage() async throws { try await runTransfer(payment: false, downloading: true, stage: "image-2") }
    @MainActor func testSwitchDuringPaymentQRDownloadPreservesStoredMethods() async throws { try await runTransfer(payment: true, downloading: true, stage: "image-1") }
    @MainActor func testNormalCardImagesUploadAsPathsAndRetainLocalBytes() async throws { try await runTransfer(payment: false, downloading: false, stage: "none") }
    @MainActor func testNormalCardImageDownloadHydratesLocalBytes() async throws { try await runTransfer(payment: false, downloading: true, stage: "none") }
    @MainActor func testNormalPaymentImageDownloadHydratesLocalBytes() async throws { try await runTransfer(payment: true, downloading: true, stage: "none") }
}

final class AssetDownloadLocalEditTests: XCTestCase {
    @MainActor private func runEdit(_ mode: String) async throws {
        let oldScope = DataOwnership.activeScope
        let email = "isolated-asset-edit-\(UUID().uuidString.lowercased())@example.invalid"
        let asset: AccountAssetStore.Asset = mode == "payment" ? .paymentMethods : .businessCard
        let baseAt = Date(timeIntervalSince1970: 1700000000)
        let remoteAt = baseAt.addingTimeInterval(60)
        let editAt = mode == "same-date" ? baseAt : baseAt.addingTimeInterval(120)
        let owner = "00000000-0000-0000-0000-000000000001"
        func png(_ color: UIColor) -> Data {
            UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { renderer in
                renderer.cgContext.setFillColor(color.cgColor)
                renderer.cgContext.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
        }
        let oldImage = png(.red)
        let newImage = png(.blue)
        let oldJSON: [String: Any] = mode == "payment"
            ? ["methods": [["id": "pay-a", "name": "Old", "qrImageData": oldImage.base64EncodedString()]]]
            : ["nickname": "Old", "portraitData": oldImage.base64EncodedString()]
        var editedJSON: [String: Any] = mode == "payment"
            ? ["methods": [["id": "pay-a", "name": "Newest", "qrImageData": newImage.base64EncodedString()]]]
            : ["nickname": "Newest", "portraitData": (mode == "avatar" || mode == "same-date" ? newImage : oldImage).base64EncodedString()]
        if mode == "date-only" { editedJSON = oldJSON }
        let oldData = try JSONSerialization.data(withJSONObject: oldJSON, options: [.sortedKeys])
        let newData = try JSONSerialization.data(withJSONObject: editedJSON, options: [.sortedKeys])
        if mode != "create" { AccountAssetStore.set(oldData, for: asset, email: email, namespace: .cloud, updatedAt: baseAt) }
        DataOwnership.activateCloud(email: email)
        defer {
            AccountAssetStore.set(nil, for: asset, email: email, namespace: .cloud)
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        let remoteObject: [String: Any] = mode == "payment"
            ? ["methods": [["id": "pay-a", "name": "Remote", "qrImagePath": "\(owner)/payment-methods/pay-a.jpg"]]]
            : ["nickname": "Remote", "portraitPath": "\(owner)/business-card/portrait.jpg"]
        var remoteSettings: [String: Any] = [asset.cloudColumn: remoteObject, "\(asset.cloudColumn)_updated_at": ISO8601DateFormatter().string(from: remoteAt)]
        var edited = false
        var writes = 0
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(forName: .accountAssetsDidSync, object: nil, queue: .main) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        func body(_ request: URLRequest) -> Data {
            if let data = request.httpBody { return data }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open();defer { stream.close() }
            var data = Data();var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break };data.append(contentsOf: buffer.prefix(count))
            }
            return data
        }
        func sendImage(_ fixture: SyncFixtureProtocol) {
            fixture.client?.urlProtocol(fixture, didReceive: HTTPURLResponse(url: fixture.request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!, cacheStoragePolicy: .notAllowed)
            fixture.client?.urlProtocol(fixture, didLoad: oldImage)
            fixture.client?.urlProtocolDidFinishLoading(fixture)
        }
        SyncFixtureProtocol.handle = { fixture in
            let path = fixture.request.url!.path
            let method = fixture.request.httpMethod ?? "GET"
            if path == "/auth/v1/user" { fixture.respond("{\"id\":\"\(owner)\"}");return }
            if path == "/rest/v1/user_settings" {
                if method == "GET" { fixture.respond(String(decoding: try! JSONSerialization.data(withJSONObject: [remoteSettings]), as: UTF8.self)) }
                else { writes += 1;remoteSettings = (try? JSONSerialization.jsonObject(with: body(fixture.request))) as? [String: Any] ?? [:];fixture.respond("{}") }
                return
            }
            if path.contains("/account-assets/") {
                if method == "POST" { fixture.respond("{}");return }
                if !edited {
                    Task { @MainActor in
                        edited = true
                        AccountAssetStore.set(mode == "clear" ? nil : newData, for: asset, email: email, namespace: .cloud, updatedAt: editAt)
                        sendImage(fixture)
                    }
                } else { sendImage(fixture) }
                return
            }
            XCTFail("Unexpected fixture request");fixture.respond("[]")
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        try await SupabaseDataSync.syncAccountAssets(email: email, accessToken: "fixture-only")
        XCTAssertTrue(edited)
        XCTAssertEqual(AccountAssetStore.data(for: asset, email: email, namespace: .cloud), mode == "clear" ? nil : newData, "Late image download must not replace a more recent local save")
        XCTAssertEqual(AccountAssetStore.updatedAt(for: asset, email: email, namespace: .cloud), mode == "clear" ? nil : editAt)
        XCTAssertEqual(notifications, 0, "Discarded cloud data must not publish a successful download notification")
        XCTAssertEqual(writes, 0)
        // Normal UI saves advance their timestamp; the next sync uploads that
        // retained revision. Same-timestamp and cache-clear cases test CAS only.
        if mode != "same-date" && mode != "clear" {
            try await SupabaseDataSync.syncAccountAssets(email: email, accessToken: "fixture-only")
            XCTAssertEqual(writes, 1)
            XCTAssertEqual(AccountAssetStore.data(for: asset, email: email, namespace: .cloud), newData)
            let uploaded = try XCTUnwrap(remoteSettings[asset.cloudColumn] as? [String: Any])
            if mode == "payment" {
                XCTAssertEqual((uploaded["methods"] as? [[String: Any]])?.first?["name"] as? String, "Newest")
            } else { XCTAssertEqual(uploaded["nickname"] as? String, mode == "date-only" ? "Old" : "Newest") }
        }
    }
    @MainActor func testNicknameSavedDuringPortraitDownloadIsPreserved() async throws { try await runEdit("nickname") }
    @MainActor func testAvatarSavedDuringPortraitDownloadIsPreserved() async throws { try await runEdit("avatar") }
    @MainActor func testPaymentMethodSavedDuringQRDownloadIsPreserved() async throws { try await runEdit("payment") }
    @MainActor func testFirstLocalCardCreatedDuringDownloadIsPreserved() async throws { try await runEdit("create") }
    @MainActor func testChangedBytesAtSameTimestampAreNotOverwrittenByPendingDownload() async throws { try await runEdit("same-date") }
    @MainActor func testResavingSameBytesAtNewTimestampRejectsPendingDownload() async throws { try await runEdit("date-only") }
    @MainActor func testCacheClearedDuringDownloadIsNotRepopulatedByLateResponse() async throws { try await runEdit("clear") }
}

final class AssetUploadLocalEditTests: XCTestCase {
    @MainActor private func runEdit(_ mode: String) async throws {
        let oldScope = DataOwnership.activeScope
        let email = "isolated-asset-upload-edit-\(UUID().uuidString.lowercased())@example.invalid"
        let primary: AccountAssetStore.Asset = mode == "payment" ? .paymentMethods : .businessCard
        let baseAt = Date(timeIntervalSince1970: 1700000000)
        let editAt = mode == "same-date" ? baseAt : baseAt.addingTimeInterval(120)
        let owner = "00000000-0000-0000-0000-000000000001"
        func png(_ color: UIColor) -> Data {
            UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { renderer in
                renderer.cgContext.setFillColor(color.cgColor)
                renderer.cgContext.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
        }
        let red = png(.red).base64EncodedString()
        let blue = png(.blue).base64EncodedString()
        let oldJSON: [String: Any] = mode == "payment"
            ? ["methods": [["id": "pay-a", "name": "Old", "qrImageData": red]]]
            : ["nickname": "Old", "portraitData": red]
        var editedJSON: [String: Any] = mode == "payment"
            ? ["methods": [["id": "pay-a", "name": "Newest", "qrImageData": blue]]]
            : ["nickname": "Newest", "portraitData": mode == "avatar" ? blue : red]
        if mode == "date-only" { editedJSON = oldJSON }
        let oldData = try JSONSerialization.data(withJSONObject: oldJSON, options: [.sortedKeys])
        let newData = try JSONSerialization.data(withJSONObject: editedJSON, options: [.sortedKeys])
        AccountAssetStore.set(oldData, for: primary, email: email, namespace: .cloud, updatedAt: baseAt)
        if mode == "other-asset" {
            let payment: [String: Any] = ["methods": [["id": "pay-a", "name": "Wallet", "qrImageData": red]]]
            AccountAssetStore.set(try JSONSerialization.data(withJSONObject: payment), for: .paymentMethods, email: email, namespace: .cloud, updatedAt: baseAt)
        }
        DataOwnership.activateCloud(email: email)
        defer {
            for asset in AccountAssetStore.Asset.allCases { AccountAssetStore.set(nil, for: asset, email: email, namespace: .cloud) }
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        var edited = false
        var payloads: [[String: Any]] = []
        var remoteSettings: [String: Any] = [:]
        func body(_ request: URLRequest) -> Data {
            if let data = request.httpBody { return data }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open();defer { stream.close() }
            var data = Data();var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break };data.append(contentsOf: buffer.prefix(count))
            }
            return data
        }
        func editAndRespond(_ fixture: SyncFixtureProtocol) {
            Task { @MainActor in
                edited = true
                AccountAssetStore.set(mode == "clear" ? nil : newData, for: primary, email: email, namespace: .cloud, updatedAt: editAt)
                fixture.respond("{}")
            }
        }
        SyncFixtureProtocol.handle = { fixture in
            let path = fixture.request.url!.path
            let method = fixture.request.httpMethod ?? "GET"
            if path == "/auth/v1/user" { fixture.respond("{\"id\":\"\(owner)\"}");return }
            if path == "/rest/v1/user_settings" {
                if method == "GET" { fixture.respond(String(decoding: try! JSONSerialization.data(withJSONObject: remoteSettings.isEmpty ? [] : [remoteSettings]), as: UTF8.self)) }
                else {
                    let payload = (try? JSONSerialization.jsonObject(with: body(fixture.request))) as? [String: Any] ?? [:]
                    payloads.append(payload)
                    remoteSettings.merge(payload) { _, new in new }
                    if mode == "in-flight" && !edited { editAndRespond(fixture) }
                    else { fixture.respond("{}") }
                }
                return
            }
            if path.contains("/account-assets/") && method == "POST" {
                XCTAssertNotNil(UIImage(data: body(fixture.request)))
                let shouldEdit = mode != "in-flight" && (mode != "other-asset" || path.contains("/payment-methods/"))
                if !edited && shouldEdit { editAndRespond(fixture) }
                else { fixture.respond("{}") }
                return
            }
            XCTFail("Unexpected fixture request");fixture.respond("[]")
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        try await SupabaseDataSync.syncAccountAssets(email: email, accessToken: "fixture-only")
        XCTAssertTrue(edited)
        XCTAssertEqual(AccountAssetStore.data(for: primary, email: email, namespace: .cloud), mode == "clear" ? nil : newData)
        XCTAssertEqual(AccountAssetStore.updatedAt(for: primary, email: email, namespace: .cloud), mode == "clear" ? nil : editAt)
        if mode == "in-flight" {
            XCTAssertEqual(payloads.count, 1, "An already sent request may commit its original snapshot")
            XCTAssertEqual((payloads.first?[primary.cloudColumn] as? [String: Any])?["nickname"] as? String, "Old")
        } else if mode == "other-asset" {
            XCTAssertEqual(payloads.count, 1)
            XCTAssertNil(payloads.first?[AccountAssetStore.Asset.businessCard.cloudColumn], "Revalidate earlier staged assets after waiting for later assets")
            XCTAssertNotNil(payloads.first?[AccountAssetStore.Asset.paymentMethods.cloudColumn])
            XCTAssertNil(payloads.first?["business_card_data_updated_at"])
        } else { XCTAssertTrue(payloads.isEmpty, "Do not publish a draft superseded during image upload") }
        if mode != "clear" {
            try await SupabaseDataSync.syncAccountAssets(email: email, accessToken: "fixture-only")
            XCTAssertEqual(AccountAssetStore.data(for: primary, email: email, namespace: .cloud), newData)
            let uploaded = try XCTUnwrap(remoteSettings[primary.cloudColumn] as? [String: Any])
            if mode == "payment" {
                XCTAssertEqual((uploaded["methods"] as? [[String: Any]])?.first?["name"] as? String, "Newest")
            } else { XCTAssertEqual(uploaded["nickname"] as? String, mode == "date-only" ? "Old" : "Newest") }
            XCTAssertEqual(remoteSettings["\(primary.cloudColumn)_updated_at"] as? String, ISO8601DateFormatter().string(from: editAt))
        }
    }
    @MainActor func testNicknameEditedDuringImageUploadDoesNotPublishOldDraft() async throws { try await runEdit("nickname") }
    @MainActor func testAvatarEditedDuringImageUploadDoesNotPublishOldDraft() async throws { try await runEdit("avatar") }
    @MainActor func testPaymentEditedDuringImageUploadDoesNotPublishOldMethods() async throws { try await runEdit("payment") }
    @MainActor func testCacheClearedDuringUploadDoesNotPublishOldDraft() async throws { try await runEdit("clear") }
    @MainActor func testSameTimestampEditDuringUploadStillInvalidatesDraft() async throws { try await runEdit("same-date") }
    @MainActor func testResaveDuringUploadStillInvalidatesDraft() async throws { try await runEdit("date-only") }
    @MainActor func testEarlierAssetChangedDuringLaterAssetUploadIsRemovedFromPatch() async throws { try await runEdit("other-asset") }
    @MainActor func testSaveDuringAlreadySentMetadataRequestRemainsForNextSync() async throws { try await runEdit("in-flight") }
}

final class ConcurrentAccountImageObjectTests: XCTestCase {
    @MainActor private func runRace(_ kind: String, large: Bool = false) async throws {
        let oldScope = DataOwnership.activeScope
        let email = "isolated-image-object-\(UUID().uuidString.lowercased())@example.invalid"
        let asset: AccountAssetStore.Asset = kind == "payment" ? .paymentMethods : .businessCard
        let owner = "00000000-0000-0000-0000-000000000001"
        let baseAt = Date(timeIntervalSince1970: 1700000000)
        func png(_ color: UIColor) -> Data {
            let size = CGSize(width: large ? 2304 : 2, height: large ? 4 : 2)
            return UIGraphicsImageRenderer(size: size).pngData { renderer in
                renderer.cgContext.setFillColor(color.cgColor)
                renderer.cgContext.fill(CGRect(origin: .zero, size: size))
            }
        }
        let legacyBytes = png(.green)
        let legacyPath = kind == "portrait" ? "\(owner)/business-card/portrait.jpg" : kind == "qr" ? "\(owner)/business-card/qr/qr-a.jpg" : "\(owner)/payment-methods/pay-a.jpg"
        func object(_ color: UIColor, _ title: String) -> [String: Any] {
            let base64 = png(color).base64EncodedString()
            switch kind {
            case "portrait": return ["nickname": title, "portraitData": base64, "portraitPath": legacyPath]
            case "qr": return ["nickname": title, "qrCodes": [["id": "qr-a", "name": title, "imageData": base64, "imagePath": legacyPath]]]
            default: return ["methods": [["id": "pay-a", "name": title, "qrImageData": base64, "qrImagePath": legacyPath]]]
            }
        }
        let oldData = try JSONSerialization.data(withJSONObject: object(.red, "Old"))
        let newData = try JSONSerialization.data(withJSONObject: object(.blue, "Newest"))
        AccountAssetStore.set(oldData, for: asset, email: email, namespace: .cloud, updatedAt: baseAt)
        DataOwnership.activateCloud(email: email)
        defer {
            AccountAssetStore.set(nil, for: asset, email: email, namespace: .cloud)
            DataOwnership.activateLocal(scope: oldScope)
            SyncFixtureProtocol.handle = nil
            URLProtocol.unregisterClass(SyncFixtureProtocol.self)
        }
        var objects: [String: Data] = [legacyPath: legacyBytes]
        var settings: [String: Any] = [:]
        var held: SyncFixtureProtocol?
        var heldPath: String?
        var heldBytes: Data?
        var newestPath: String?
        var newestBytes: Data?
        var uploads = 0
        var metadataWrites = 0
        let oldUploadStarted = expectation(description: "Old image upload suspended before commit")
        func body(_ request: URLRequest) -> Data {
            if let data = request.httpBody { return data }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open();defer { stream.close() }
            var data = Data();var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break };data.append(contentsOf: buffer.prefix(count))
            }
            return data
        }
        SyncFixtureProtocol.handle = { fixture in
            let path = fixture.request.url!.path
            let method = fixture.request.httpMethod ?? "GET"
            if path == "/auth/v1/user" { fixture.respond("{\"id\":\"\(owner)\"}");return }
            if path == "/rest/v1/user_settings" {
                if method == "GET" { fixture.respond(String(decoding: try! JSONSerialization.data(withJSONObject: settings.isEmpty ? [] : [settings]), as: UTF8.self)) }
                else { metadataWrites += 1;settings.merge((try? JSONSerialization.jsonObject(with: body(fixture.request))) as? [String: Any] ?? [:]) { _, new in new };fixture.respond("{}") }
                return
            }
            if path.contains("/account-assets/") && method == "POST" {
                uploads += 1
                let key = path.components(separatedBy: "/account-assets/").last!
                let bytes = body(fixture.request)
                let image = UIImage(data: bytes)
                XCTAssertNotNil(image)
                if let image { XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 2048) }
                let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                XCTAssertEqual(URL(fileURLWithPath: key).deletingPathExtension().lastPathComponent, digest, "Address must hash the exact normalized bytes sent to Storage")
                if uploads == 1 {
                    held = fixture;heldPath = key;heldBytes = bytes;oldUploadStarted.fulfill()
                } else {
                    objects[key] = bytes;newestPath = key;newestBytes = bytes
                    fixture.respond("{}")
                }
                return
            }
            XCTFail("Unexpected fixture request");fixture.respond("[]")
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        let older = Task { @MainActor in try await SupabaseDataSync.syncAccountAssets(email: email, accessToken: "fixture-only") }
        await fulfillment(of: [oldUploadStarted], timeout: 5)
        AccountAssetStore.set(newData, for: asset, email: email, namespace: .cloud, updatedAt: baseAt.addingTimeInterval(60))
        do {
            try await SupabaseDataSync.syncAccountAssets(email: email, accessToken: "fixture-only")
        } catch {
            held?.client?.urlProtocol(held!, didFailWithError: URLError(.cancelled))
            _ = try? await older.value
            throw error
        }
        // Let the stale bytes commit last, exactly as delayed Storage can do.
        if let key = heldPath, let bytes = heldBytes { objects[key] = bytes }
        held?.respond("{}")
        try await older.value
        let newPath = try XCTUnwrap(newestPath)
        let oldPath = try XCTUnwrap(heldPath)
        XCTAssertNotEqual(oldPath, newPath, "Different image bytes must never share a mutable object address")
        XCTAssertEqual(objects[newPath], newestBytes, "Late old upload must not replace the currently referenced image")
        XCTAssertEqual(objects[legacyPath], legacyBytes, "Migration must leave the existing legacy object unchanged")
        XCTAssertEqual(objects.count, 3)
        XCTAssertEqual(metadataWrites, 1, "The superseded local draft must not publish metadata")
        let remote = try XCTUnwrap(settings[asset.cloudColumn] as? [String: Any])
        let referenced: String?
        if kind == "portrait" { referenced = remote["portraitPath"] as? String }
        else if kind == "qr" { referenced = (remote["qrCodes"] as? [[String: Any]])?.first?["imagePath"] as? String }
        else { referenced = (remote["methods"] as? [[String: Any]])?.first?["qrImagePath"] as? String }
        XCTAssertEqual(referenced, newPath)
        XCTAssertEqual(AccountAssetStore.data(for: asset, email: email, namespace: .cloud), newData)
        // A retry with identical local bytes reuses the address and object.
        try await SupabaseDataSync.syncAccountAssets(email: email, accessToken: "fixture-only")
        XCTAssertEqual(newestPath, newPath)
        XCTAssertEqual(objects.count, 3)
        XCTAssertEqual(objects[newPath], newestBytes)
    }
    @MainActor func testLargePortraitAddressHashesResizedPayload() async throws { try await runRace("portrait", large: true) }
    @MainActor func testLateOldPortraitUploadCannotReplaceNewPortrait() async throws { try await runRace("portrait") }
    @MainActor func testLateOldCardQRUploadCannotReplaceNewQR() async throws { try await runRace("qr") }
    @MainActor func testLateOldPaymentQRUploadCannotReplaceNewQR() async throws { try await runRace("payment") }
}

final class Tours4FunRecognitionTests: XCTestCase {
    // Same structured format as the supplied order; guest identity is anonymized.
    private let text = """
    订单号：C-1234567-US
    接机日期：11/25  航班号：JX2，抵达机场：LAX
    接机时间：预计19:00 到达
    类型：接机
    客人地址： Pasadena Hotel & Pool 住址：928 E Colorado Blvd #101, Pasadena, CA 91106美國
    联络人：QA GUEST（3人）
    联络电话：886-900000001（台湾）
    人数：3人，5件行李
    """
    private func now(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    func testStructuredFieldsDoNotConfuseOrderPhoneOrRepeatedCounts() throws {
        let result = try XCTUnwrap(PickupOrderRecognizer.recognize(text, now: now(2026, 10, 25)))
        XCTAssertEqual(result.orderNumber, "C-1234567-US")
        XCTAssertEqual(result.dateText, "2026-11-25")
        XCTAssertEqual(result.flight, "JX2")
        XCTAssertEqual(result.airport, "LAX")
        XCTAssertEqual(result.estimatedArrival, "19:00")
        XCTAssertEqual(result.contact, "QA GUEST")
        XCTAssertEqual(result.phone, "+886900000001")
        XCTAssertEqual(result.passengers, "3")
        XCTAssertEqual(result.luggage, "5")
        XCTAssertEqual(result.hotel, "Pasadena Hotel & Pool")
        XCTAssertEqual(result.address, "928 E Colorado Blvd #101, Pasadena, CA 91106美國")
    }
    func testPastMonthDayRollsToNextYear() throws {
        XCTAssertEqual(try XCTUnwrap(PickupOrderRecognizer.recognize(text, now: now(2026, 11, 26))).dateText, "2027-11-25")
    }
    func testSameDayStaysThisYearEvenAfterArrivalHour() throws {
        XCTAssertEqual(try XCTUnwrap(PickupOrderRecognizer.recognize(text, now: now(2026, 11, 25, hour: 23))).dateText, "2026-11-25")
    }
    func testExplicitYearIsNeverRolledForward() throws {
        let result = try XCTUnwrap(PickupOrderRecognizer.recognize(text.replacingOccurrences(of: "11/25", with: "2025/11/25"), now: now(2026, 10, 25)))
        XCTAssertEqual(result.dateText, "2025-11-25")
        XCTAssertFalse(result.inferredYear)
    }
    func testReferenceDayUsesLosAngelesInsteadOfUTC() throws {
        let instant = ISO8601DateFormatter().date(from: "2027-01-01T02:00:00Z")!
        XCTAssertEqual(try XCTUnwrap(PickupOrderRecognizer.recognize(text.replacingOccurrences(of: "11/25", with: "12/31"), now: instant)).dateText, "2026-12-31")
    }
    func testYearEndJanuaryRollover() throws {
        XCTAssertEqual(try XCTUnwrap(PickupOrderRecognizer.recognize(text.replacingOccurrences(of: "11/25", with: "1/1"), now: now(2026, 12, 31))).dateText, "2027-01-01")
    }
    func testInvalidDateIsNotNormalized() throws {
        XCTAssertNil(try XCTUnwrap(PickupOrderRecognizer.recognize(text.replacingOccurrences(of: "11/25", with: "2/30"), now: now(2026, 1, 1))).date)
    }
    func testLeapDateUsesInferredTargetYear() throws {
        XCTAssertEqual(try XCTUnwrap(PickupOrderRecognizer.recognize(text.replacingOccurrences(of: "11/25", with: "2/29"), now: now(2027, 10, 25))).dateText, "2028-02-29")
        XCTAssertNil(try XCTUnwrap(PickupOrderRecognizer.recognize(text.replacingOccurrences(of: "11/25", with: "2/29"), now: now(2026, 10, 25))).date)
    }
    func testNBSPAndASCIILabelSeparators() throws {
        let value = text.replacingOccurrences(of: "：", with: ":").replacingOccurrences(of: "Pasadena Hotel", with: "\u{00a0}Pasadena Hotel")
        XCTAssertEqual(try XCTUnwrap(PickupOrderRecognizer.recognize(value, now: now(2026, 10, 25))).hotel, "Pasadena Hotel & Pool")
    }
    func testUnknownFormatOrAirportDoesNotInventProviderOrTimezone() {
        XCTAssertNil(PickupOrderRecognizer.recognize("明天9点张先生接机"))
        XCTAssertNil(PickupOrderRecognizer.recognize(text.replacingOccurrences(of: "C-1234567-US", with: "OTHER-123")))
        XCTAssertNil(PickupOrderRecognizer.recognize(text.replacingOccurrences(of: "LAX", with: "JFK")))
    }
    @MainActor func testApplySetsPickupAndTwoRemindersKeepsQuoteAndUsesDedicatedOrderNumber() throws {
        let result = try XCTUnwrap(PickupOrderRecognizer.recognize(text, now: now(2026, 10, 25)))
        var form = NewTripFormModel()
        form.TripPrice = 123;form.appointmentTime = now(2026, 10, 25, hour: 8)
        let appointment = form.appointmentTime
        form.TripMemo = "Existing manual note"
        form.travelAgencyName = "Other";form.travelAgencyCode = "OTHER"
        form.selectedCustomerUUID = UUID().uuidString
        form.flightSelectionSnapshotJSON = "stale"
        result.apply(to: &form, now: now(2026, 10, 25))
        XCTAssertEqual(form.orderSource, "旅行社订单")
        XCTAssertEqual(form.travelAgencyName, "途风")
        XCTAssertEqual(form.travelAgencyCode, "")
        XCTAssertEqual(form.customerName, "QA GUEST")
        XCTAssertNil(form.selectedCustomerUUID)
        XCTAssertEqual(form.customerCount, "3");XCTAssertEqual(form.customerStuff, "5")
        XCTAssertEqual(form.flightInfo, "JX2");XCTAssertEqual(form.locationStart, "LAX")
        XCTAssertEqual(form.appointmentDate, result.date);XCTAssertEqual(form.flightdate, result.date)
        XCTAssertEqual(form.appointmentTime, result.pickupDateTime)
        XCTAssertNotEqual(form.appointmentTime, appointment)
        XCTAssertEqual(form.travelAgencyOrderNumber, "C-1234567-US")
        XCTAssertTrue(form.reminderEnabled);XCTAssertTrue(form.hasSecondReminder)
        XCTAssertEqual(form.TripPrice, 123)
        XCTAssertTrue(form.TripMemo.hasPrefix("Existing manual note"))
        XCTAssertTrue(form.TripMemo.contains("途风订单号：C-1234567-US"))
        XCTAssertTrue(form.TripMemo.contains("19:00"))
        XCTAssertEqual(form.flightSelectionSnapshotJSON, "")
        let memo = form.TripMemo
        result.apply(to: &form, agencyCode: "TF", now: now(2026, 10, 25))
        XCTAssertEqual(form.TripMemo, memo)
        XCTAssertEqual(form.travelAgencyCode, "TF")
    }
    @MainActor func testCloudEditorUsesArrivalAsPickupAndEnablesTwoReminders() throws {
        let result = try XCTUnwrap(PickupOrderRecognizer.recognize(text, now: now(2026, 10, 25)))
        let form = CloudSmartInputHarness()
        let time = form.appointmentTime
        form.applyRecognizedOrder(result)
        XCTAssertEqual(form.agencyName, "途风");XCTAssertEqual(form.agencyCode, "TF")
        XCTAssertEqual(form.orderSource, "旅行社订单");XCTAssertEqual(form.customerID, "")
        XCTAssertEqual(form.customerName, "QA GUEST");XCTAssertEqual(form.customerContact, "+886900000001")
        XCTAssertEqual(form.customerCount, "3");XCTAssertEqual(form.customerStuff, "5")
        XCTAssertEqual(form.start, "LAX");XCTAssertEqual(form.flightNumber, "JX2")
        XCTAssertEqual(form.appointmentDate, result.date);XCTAssertEqual(form.flightDate, result.date)
        XCTAssertEqual(form.appointmentTime, result.pickupDateTime);XCTAssertNotEqual(form.appointmentTime, time)
        XCTAssertEqual(form.agencyOrderNumber, "C-1234567-US")
        XCTAssertTrue(form.reminderEnabled);XCTAssertTrue(form.hasSecondReminder)
        XCTAssertLessThan(form.reminderDate, form.secondReminderDate)
        XCTAssertEqual(form.price, "123");XCTAssertEqual(form.tip, "5")
        XCTAssertTrue(form.destination.contains("#101"));XCTAssertTrue(form.memo.contains("C-1234567-US"))
        XCTAssertEqual(form.invalidations, 1)
    }
    @MainActor func testDuplicateAgencyNamesDoNotChooseArbitraryCode() throws {
        let result = try XCTUnwrap(PickupOrderRecognizer.recognize(text, now: now(2026, 10, 25)))
        let form = CloudSmartInputHarness()
        form.directory.agencies.append(.init(name: "途风", agencyCode: "TF2"))
        form.applyRecognizedOrder(result)
        XCTAssertEqual(form.agencyName, "途风")
        XCTAssertEqual(form.agencyCode, "")
    }
    @MainActor func testCloudEditorInvalidDateLeavesDraftUntouched() throws {
        let result = try XCTUnwrap(PickupOrderRecognizer.recognize(text.replacingOccurrences(of: "11/25", with: "13/25")))
        let form = CloudSmartInputHarness()
        form.applyRecognizedOrder(result)
        XCTAssertEqual(form.customerName, "Keep");XCTAssertEqual(form.agencyCode, "OTHER")
        XCTAssertEqual(form.invalidations, 0)
    }
    @MainActor func testInvalidDateCannotApplyToDraft() throws {
        let result = try XCTUnwrap(PickupOrderRecognizer.recognize(text.replacingOccurrences(of: "11/25", with: "13/25")))
        var form = NewTripFormModel();form.customerName = "Keep"
        result.apply(to: &form, now: now(2026, 10, 25))
        XCTAssertEqual(form.customerName, "Keep")
        XCTAssertEqual(form.orderSource, "普通客户")
    }
}

final class AgencyOrderAndSmartReminderTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    private func date(_ year: Int = 2026, _ month: Int = 11, _ day: Int = 25, _ hour: Int = 19, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
    func testFallBackRepeatedHourKeepsFutureAbsoluteReminderInstants() throws {
        let formatter = ISO8601DateFormatter()
        let pickup = try XCTUnwrap(formatter.date(from:"2026-11-01T10:30:00Z"))
        let now = try XCTUnwrap(formatter.date(from:"2026-11-01T09:00:00Z"))
        let first = try XCTUnwrap(formatter.date(from:"2026-11-01T09:30:00Z"))
        let second = try XCTUnwrap(formatter.date(from:"2026-11-01T10:00:00Z"))
        XCTAssertEqual(SmartPickupReminderPlan.dates(before:pickup,now:now,calendar:calendar),[first,second])
    }
    func testNotificationTriggerKeepsSecondRepeatedHourAndExplicitTimezone() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from:"2027-11-07T09:30:00Z"))
        let trigger = TripReminderScheduler.trigger(for:date)
        let components = trigger.dateComponents
        XCTAssertEqual(components.timeZone?.secondsFromGMT(for:date),0)
        XCTAssertEqual(components.calendar?.date(from:components),date)
        XCTAssertEqual(trigger.nextTriggerDate(),date)
        XCTAssertFalse(trigger.repeats)
    }
    func testDefaultTwoRemindersArePreviousDayAndTwoHoursBefore() {
        let pickup = date()
        XCTAssertEqual(SmartPickupReminderPlan.dates(before: pickup, now: date(2026,10,25), calendar: calendar), [date(2026,11,24,19),date(2026,11,25,17)])
    }
    func testSameDayRemindersSkipExpiredDefaults() {
        XCTAssertEqual(SmartPickupReminderPlan.dates(before: date(), now: date(2026,11,25,16,30), calendar: calendar), [date(2026,11,25,17),date(2026,11,25,18)])
    }
    func testVeryNearPickupFindsTwoDistinctFutureMinutes() {
        let now = date(2026,11,25,18,57).addingTimeInterval(30)
        let values = SmartPickupReminderPlan.dates(before: date(), now: now, calendar: calendar)
        XCTAssertEqual(values, [date(2026,11,25,18,58),date(2026,11,25,18,59)])
        XCTAssertTrue(values.allSatisfy { $0 > now && $0 < date() })
    }
    func testTooLateOrPastPickupCannotInventTwoValidReminders() {
        XCTAssertTrue(SmartPickupReminderPlan.dates(before: date(), now: date(2026,11,25,18,59), calendar: calendar).isEmpty)
        XCTAssertTrue(SmartPickupReminderPlan.dates(before: date(), now: date(2026,11,25,20), calendar: calendar).isEmpty)
    }
    func testPreviousDayUsesWallClockAcrossDaylightSaving() {
        let pickup = date(2027,3,14,19)
        let values = SmartPickupReminderPlan.dates(before: pickup, now: date(2027,3,10,12), calendar: calendar)
        XCTAssertEqual(values.first, date(2027,3,13,19))
        XCTAssertEqual(pickup.timeIntervalSince(values[0]), 23 * 3600)
    }
    @MainActor func testAgencyOrderNumberSurvivesSaveReadEditAndCopy() throws {
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let context = ModelContext(container)
        var form = NewTripFormModel()
        form.orderSource = "旅行社订单";form.travelAgencyName = "途风";form.travelAgencyCode = "TF"
        form.travelAgencyOrderNumber = " C-1234567-US "
        form.appointmentDate = date();form.appointmentTime = date()
        form.reminderEnabled = true;form.hasSecondReminder = true
        form.reminderDateTime = date(2026,11,24,19);form.secondReminderDateTime = date(2026,11,25,17)
        let booking = TripBookingRecord(form: form);context.insert(booking);try context.save()
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TripBookingRecord>()).first)
        XCTAssertEqual(saved.travelAgencyOrderNumber,"C-1234567-US")
        XCTAssertEqual(saved.travelAgencyCode,"TF")
        XCTAssertEqual(NewTripFormModel(booking:saved).travelAgencyOrderNumber,"C-1234567-US")
        XCTAssertEqual(TripBookingRecord(copying:saved).travelAgencyOrderNumber,"C-1234567-US")
        XCTAssertTrue(saved.reminderEnabled);XCTAssertTrue(saved.hasSecondReminder)
        XCTAssertEqual(saved.reminderDateTime,form.reminderDateTime);XCTAssertEqual(saved.secondReminderDateTime,form.secondReminderDateTime)
        form.travelAgencyOrderNumber="C-7654321-US";booking.update(from:form);try context.save()
        XCTAssertEqual(booking.travelAgencyOrderNumber,"C-7654321-US")
        form.orderSource="普通客户";booking.update(from:form);try context.save()
        XCTAssertEqual(booking.travelAgencyOrderNumber,"")
    }
    @MainActor func testOrdinaryOrderNeverPersistsHiddenAgencyOrderNumber() {
        var form=NewTripFormModel();form.travelAgencyOrderNumber="SHOULD-NOT-SAVE"
        XCTAssertEqual(TripBookingRecord(form:form).travelAgencyOrderNumber,"")
    }
    @MainActor private func runUpload(agency: Bool) async throws {
        let oldScope=DataOwnership.activeScope
        let email="isolated-order-field@example.invalid"
        DataOwnership.activateCloud(email:email)
        defer { DataOwnership.activateLocal(scope:oldScope);SyncFixtureProtocol.handle=nil;URLProtocol.unregisterClass(SyncFixtureProtocol.self) }
        let schema=Schema(AppDataSchema.modelTypes)
        let container=try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,isStoredInMemoryOnly:true)])
        let context=ModelContext(container)
        var form=NewTripFormModel();form.orderSource=agency ? "旅行社订单":"普通客户"
        form.travelAgencyCode="TF";form.travelAgencyOrderNumber="C-1234567-US"
        let booking=TripBookingRecord(form:form);context.insert(booking);try context.save()
        var posted=false
        SyncFixtureProtocol.handle={ fixture in
            let path=fixture.request.url!.path
            if path=="/auth/v1/user" { fixture.respond("{\"id\":\"00000000-0000-0000-0000-000000000001\"}");return }
            if path=="/rest/v1/trips" && fixture.request.httpMethod=="POST" {
                posted=true
                var data=fixture.request.httpBody ?? Data()
                if data.isEmpty,let stream=fixture.request.httpBodyStream {
                    stream.open();defer{stream.close()};var buffer=[UInt8](repeating:0,count:4096)
                    while stream.hasBytesAvailable {let n=stream.read(&buffer,maxLength:buffer.count);if n<=0{break};data.append(contentsOf:buffer.prefix(n))}
                }
                let rows=(try? JSONSerialization.jsonObject(with:data)) as? [[String:Any]]
                XCTAssertEqual(rows?.first?["travel_agency_order_number"] as? String,agency ? "C-1234567-US":"")
                XCTAssertNotEqual(rows?.first?["travel_agency_order_number"] as? String,"TF")
            }
            fixture.respond("[]")
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        _=try await SupabaseDataSync.uploadLocalData(context:context,accessToken:"fixture-only",accountEmail:email)
        XCTAssertTrue(posted)
    }
    @MainActor func testSyncUploadsSeparateAgencyOrderNumberColumn() async throws {try await runUpload(agency:true)}
    @MainActor func testSyncOrdinaryOrderSendsEmptyAgencyOrderNumber() async throws {try await runUpload(agency:false)}
}

final class CloudAgencyOrderReadbackTests: XCTestCase {
    @MainActor private func fetch(number: String?, source: String) async throws -> CloudOnlineRepository.CloudTripRecord {
        let owner="00000000-0000-0000-0000-000000000001"
        let email="isolated-agency-readback@example.invalid"
        var row:[String:Any] = [
            "id":"00000000-0000-0000-0000-000000000002","service_type":"接机","order_source":source,
            "travel_agency_code":"TF","travel_agency_name":"途风","customer_name":"QA Guest",
            "customer_contact":"fixture","customer_count":"3","customer_stuff":"5",
            "appointment_date":"2026-11-25T20:00:00Z","appointment_time":"2026-11-26T03:00:00Z",
            "location_start":"LAX","location_end":"Fixture hotel","flight_info":"JX2","flight_date":"2026-11-25T20:00:00Z",
            "memo":"","price":90,"tip":0,"is_paid":false,"is_completed":false,"is_cancelled":false,
            "reminder_enabled":true,"has_second_reminder":true,"reminder_at":"2026-11-25T03:00:00Z",
            "second_reminder_at":"2026-11-26T01:00:00Z","currency_code":"USD","created_at":"2026-10-25T00:00:00Z"
        ]
        if let number {row["travel_agency_order_number"]=number}
        let json=String(decoding:try JSONSerialization.data(withJSONObject:[row]),as:UTF8.self)
        SyncFixtureProtocol.handle={ fixture in
            XCTAssertEqual(fixture.request.httpMethod,"GET")
            if fixture.request.url!.path=="/auth/v1/user" {fixture.respond("{\"id\":\"\(owner)\",\"email\":\"\(email)\"}")}
            else if fixture.request.url!.path=="/rest/v1/trips" {fixture.respond(json)}
            else {fixture.respond("[]")}
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer{SyncFixtureProtocol.handle=nil;URLProtocol.unregisterClass(SyncFixtureProtocol.self)}
        let trips=try await CloudOnlineRepository.fetchTrips(account:.init(id:owner,email:email),accessToken:"fixture-only")
        return try XCTUnwrap(trips.first)
    }
    @MainActor func testNewCloudOrderNumberReadsSeparatelyFromAgencyCode() async throws {
        let trip=try await fetch(number:"C-1234567-US",source:"旅行社订单")
        XCTAssertEqual(trip.travelAgencyOrderNumber,"C-1234567-US");XCTAssertEqual(trip.travelAgencyCode,"TF")
        XCTAssertTrue(trip.reminderEnabled);XCTAssertTrue(trip.hasSecondReminder)
        XCTAssertEqual(trip.reminderAt,"2026-11-25T03:00:00Z");XCTAssertEqual(trip.secondReminderAt,"2026-11-26T01:00:00Z")
    }
    @MainActor func testLegacyCloudRowWithoutColumnRemainsReadable() async throws {
        let trip = try await fetch(number:nil,source:"旅行社订单")
        XCTAssertEqual(trip.travelAgencyOrderNumber,"")
    }
    @MainActor func testOrdinaryCloudRowDoesNotExposeStrayAgencyNumber() async throws {
        let trip = try await fetch(number:"SHOULD-NOT-SHOW",source:"普通客户")
        XCTAssertEqual(trip.travelAgencyOrderNumber,"")
    }
}

final class AgencyOrderRecoveryTests: XCTestCase {
    @MainActor private func resolve(keepRemote: Bool, restoreDeleted: Bool = false, ordinary: Bool = false) throws {
        let scope = DataOwnership.activeScope
        DataOwnership.activateCloud(email:"isolated-order-recovery@example.invalid")
        defer { DataOwnership.activateLocal(scope:scope) }
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,isStoredInMemoryOnly:true)])
        let context = ModelContext(container)
        var form = NewTripFormModel()
        form.orderSource = "旅行社订单";form.travelAgencyOrderNumber = "LOCAL-ORDER"
        form.reminderEnabled = true;form.hasSecondReminder = true
        form.reminderDateTime = Date(timeIntervalSince1970:1800000000)
        form.secondReminderDateTime = Date(timeIntervalSince1970:1800003600)
        let local = TripBookingRecord(form:form)
        let id = local.id
        if !restoreDeleted { context.insert(local) }
        let row: [String:Any] = ["id":id.uuidString,"order_source":ordinary ? "普通客户":"旅行社订单",
            "travel_agency_order_number":"REMOTE-ORDER","reminder_enabled":true,"has_second_reminder":true,
            "reminder_at":"2026-11-25T03:00:00Z","second_reminder_at":"2026-11-26T01:00:00Z",
            "appointment_date":"2026-11-25T20:00:00Z","appointment_time":"2026-11-26T03:00:00Z",
            "flight_date":"2026-11-25T20:00:00Z"]
        let conflict = CloudSyncConflict(tableName:"trips",recordID:id.uuidString.lowercased(),
            ownerScope:DataOwnership.activeScope,localUpdatedAt:.now,remoteUpdatedAt:.now.addingTimeInterval(3600),
            remotePayloadJSON:String(decoding:try JSONSerialization.data(withJSONObject:row),as:UTF8.self),isLocalDeletion:restoreDeleted)
        context.insert(conflict);try context.save()
        try SupabaseDataSync.resolveConflict(conflict,keepRemote:keepRemote,context:context)
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TripBookingRecord>()).first)
        XCTAssertEqual(saved.id,id)
        XCTAssertEqual(saved.travelAgencyOrderNumber,keepRemote ? (ordinary ? "":"REMOTE-ORDER"):"LOCAL-ORDER")
        XCTAssertTrue(saved.reminderEnabled);XCTAssertTrue(saved.hasSecondReminder)
        let expectedFirst = keepRemote ? ISO8601DateFormatter().date(from:"2026-11-25T03:00:00Z"):form.reminderDateTime
        let expectedSecond = keepRemote ? ISO8601DateFormatter().date(from:"2026-11-26T01:00:00Z"):form.secondReminderDateTime
        XCTAssertEqual(saved.reminderDateTime,expectedFirst);XCTAssertEqual(saved.secondReminderDateTime,expectedSecond)
        XCTAssertTrue(try context.fetch(FetchDescriptor<CloudSyncConflict>()).isEmpty)
    }
    @MainActor func testAcceptRemoteConflictKeepsOrderNumberAndBothReminders() throws {try resolve(keepRemote:true)}
    @MainActor func testKeepLocalConflictKeepsOrderNumberAndBothReminders() throws {try resolve(keepRemote:false)}
    @MainActor func testRestoreDeletedTripReconstructsOrderNumberAndBothReminders() throws {try resolve(keepRemote:true,restoreDeleted:true)}
    @MainActor func testRemoteOrdinaryOrderClearsHiddenAgencyNumber() throws {try resolve(keepRemote:true,ordinary:true)}
    @MainActor func testDiskReopenPreservesOrderNumberAndBothReminders() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agency-order-\(UUID().uuidString).store")
        let schema = Schema(AppDataSchema.modelTypes)
        func open() throws -> ModelContainer {
            try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,url:url)])
        }
        let first = Date(timeIntervalSince1970:1800000000),second = first.addingTimeInterval(7200)
        try autoreleasepool {
            let container = try open();let context = ModelContext(container)
            var form = NewTripFormModel();form.orderSource = "旅行社订单";form.travelAgencyOrderNumber = "QA-DISK-ORDER"
            form.reminderEnabled = true;form.hasSecondReminder = true;form.reminderDateTime = first;form.secondReminderDateTime = second
            context.insert(TripBookingRecord(form:form));try context.save()
        }
        let container = try open()
        let saved = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<TripBookingRecord>()).first)
        XCTAssertEqual(saved.travelAgencyOrderNumber,"QA-DISK-ORDER")
        XCTAssertTrue(saved.reminderEnabled);XCTAssertTrue(saved.hasSecondReminder)
        XCTAssertEqual(saved.reminderDateTime,first);XCTAssertEqual(saved.secondReminderDateTime,second)
    }
}


final class CloudSecondReminderDefaultsTests: XCTestCase {
    @MainActor func testAddingSecondReminderNearPickupUsesFutureTime() {
        let form = CloudSmartInputHarness()
        let pickup = form.recognitionNow.addingTimeInterval(30 * 60)
        form.appointmentDate = pickup;form.appointmentTime = pickup
        form.reminderDate = form.recognitionNow.addingTimeInterval(10 * 60)
        form.hasSecondReminder = true
        form.updateSecondReminderDefault()
        XCTAssertTrue(form.hasSecondReminder)
        XCTAssertGreaterThan(form.secondReminderDate,form.recognitionNow)
        XCTAssertLessThan(form.secondReminderDate,pickup)
        XCTAssertNotEqual(form.secondReminderDate,form.reminderDate)
    }
    @MainActor func testAddingSecondReminderDoesNotDuplicateFirstDefault() {
        let form = CloudSmartInputHarness()
        let pickup = form.recognitionNow.addingTimeInterval(3 * 3600)
        form.appointmentDate = pickup;form.appointmentTime = pickup
        form.reminderDate = pickup.addingTimeInterval(-2 * 3600)
        form.hasSecondReminder = true
        form.updateSecondReminderDefault()
        XCTAssertTrue(form.hasSecondReminder)
        XCTAssertNotEqual(form.secondReminderDate,form.reminderDate)
        XCTAssertGreaterThan(form.secondReminderDate,form.recognitionNow)
    }
    @MainActor func testAddingSecondReminderWithoutTwoFutureMinutesDoesNotEnableIt() {
        let form = CloudSmartInputHarness()
        let pickup = form.recognitionNow.addingTimeInterval(30)
        form.appointmentDate = pickup;form.appointmentTime = pickup
        form.hasSecondReminder = true
        form.updateSecondReminderDefault()
        XCTAssertFalse(form.hasSecondReminder)
    }
}


final class CloudDraftRetryIdentityTests: XCTestCase {
    @MainActor func testNewDraftKeepsSameIDForRetry() {
        let form = CloudDraftIdentityHarness()
        let first = form.saveID()
        XCTAssertEqual(form.saveID(),first)
        XCTAssertNotNil(UUID(uuidString:first))
    }
    @MainActor func testCopiedDraftRetriesSameNewIDInsteadOfOriginal() {
        let form = CloudDraftIdentityHarness()
        form.trip = .init(id:UUID().uuidString.lowercased());form.copyAsNew = true
        let first = form.saveID()
        XCTAssertNotEqual(first,form.trip?.id)
        XCTAssertEqual(form.saveID(),first)
    }
    @MainActor func testExistingTripKeepsOriginalIDAndSeparateDraftsDiffer() {
        let form = CloudDraftIdentityHarness()
        let original = UUID().uuidString.lowercased();form.trip = .init(id:original)
        XCTAssertEqual(form.saveID(),original)
        XCTAssertNotEqual(CloudDraftIdentityHarness().saveID(),CloudDraftIdentityHarness().saveID())
    }
}

final class CloudDraftAmbiguousSaveTests: XCTestCase {
    @MainActor private func run(copy: Bool) async throws {
        let owner = "00000000-0000-0000-0000-000000000001"
        let account = CloudOnlineRepository.Account(id:owner,email:"isolated-retry@example.invalid")
        let form = CloudDraftIdentityHarness();form.copyAsNew = copy
        if copy { form.trip = .init(id:UUID().uuidString.lowercased()) }
        var stored:[String:[String:Any]] = [:]
        var writes = 0
        SyncFixtureProtocol.handle = { fixture in
            if fixture.request.url!.path == "/auth/v1/user" {
                fixture.respond("{\"id\":\"\(owner)\",\"email\":\"isolated-retry@example.invalid\"}");return
            }
            XCTAssertEqual(fixture.request.url!.path,"/rest/v1/rpc/save_online_trip")
            XCTAssertEqual(fixture.request.httpMethod,"POST")
            var data = fixture.request.httpBody ?? Data()
            if data.isEmpty, let stream = fixture.request.httpBodyStream {
                stream.open();defer { stream.close() };var buffer = [UInt8](repeating:0,count:4096)
                while stream.hasBytesAvailable { let n=stream.read(&buffer,maxLength:buffer.count);if n<=0 { break };data.append(contentsOf:buffer.prefix(n)) }
            }
            let body = try! JSONSerialization.jsonObject(with:data) as! [String:Any]
            let trip = body["p_trip"] as! [String:Any]
            let id = trip["id"] as! String
            XCTAssertEqual(trip["travel_agency_order_number"] as? String,"QA-RETRY-ORDER")
            XCTAssertEqual(trip["appointment_time"] as? String,"2026-11-26T03:00:00Z")
            XCTAssertEqual(trip["reminder_enabled"] as? Bool,true)
            XCTAssertEqual(trip["has_second_reminder"] as? Bool,true)
            XCTAssertEqual(trip["reminder_at"] as? String,"2026-11-25T03:00:00Z")
            XCTAssertEqual(trip["second_reminder_at"] as? String,"2026-11-26T01:00:00Z")
            XCTAssertEqual((body["p_stops"] as? [[String:Any]])?.count,1)
            XCTAssertEqual((body["p_expenses"] as? [[String:Any]])?.count,1)
            stored[id] = trip;writes += 1
            if writes == 1 { fixture.client?.urlProtocol(fixture,didFailWithError:URLError(.networkConnectionLost)) }
            else { fixture.respond("null") }
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer { SyncFixtureProtocol.handle=nil;URLProtocol.unregisterClass(SyncFixtureProtocol.self) }
        for attempt in 0..<2 {
            let row:[String:Any] = ["id":form.saveID(),"order_source":"旅行社订单","travel_agency_order_number":"QA-RETRY-ORDER",
                "appointment_time":"2026-11-26T03:00:00Z","reminder_enabled":true,"has_second_reminder":true,
                "reminder_at":"2026-11-25T03:00:00Z","second_reminder_at":"2026-11-26T01:00:00Z"]
            do {
                try await CloudOnlineRepository.saveTrip(trip:row,stops:[["address":"Fixture stop"]],expenses:[["title":"Fixture expense","amount":1]],account:account,accessToken:"fixture-only")
                XCTAssertEqual(attempt,1)
            } catch { if attempt != 0 { throw error } }
        }
        XCTAssertEqual(writes,2);XCTAssertEqual(stored.count,1)
        XCTAssertNotEqual(stored.keys.first,form.trip?.id)
    }
    @MainActor func testNewDraftResponseLostAfterCommitRetriesOneIdentityWithFullPayload() async throws {try await run(copy:false)}
    @MainActor func testCopiedDraftResponseLostAfterCommitRetriesOneIdentityWithFullPayload() async throws {try await run(copy:true)}
}


final class RecognizedOrderFlightHandoffTests: XCTestCase {
    private let raw = """
    订单号：C-1234567-US
    接机日期：11/25 航班号：JX2，抵达机场：LAX
    接机时间：预计19:00 到达
    类型：接机
    客人地址：QA Hotel 住址：100 QA Street #101
    联络人：QA GUEST（3人）
    联络电话：886-900000001
    人数：3人，5件行李
    """
    @MainActor private func draft() throws -> LocalFlightRaceHarness {
        let result = try XCTUnwrap(PickupOrderRecognizer.recognize(raw,now:Date(timeIntervalSince1970:1792929600)))
        let form = LocalFlightRaceHarness()
        result.apply(to:&form.formData,now:Date(timeIntervalSince1970:1792929600))
        return form
    }
    private func candidate(arrival:String,depTerminal:String?,arrTerminal:String?) -> VariFlightLookupResult {
        .init(airlineName:"Fixture",departureAirport:"TPE",arrivalAirport:"LAX",departureTerminal:depTerminal,
              arrivalTerminal:arrTerminal,departureTime:"15:00",estimatedArrivalTime:arrival,baggageCarousel:"4")
    }
    @MainActor func testChoosingFlightPreservesRecognizedPickupAndReminders() async throws {
        let form = try draft()
        let pickup=form.formData.appointmentTime,first=form.formData.reminderDateTime,second=form.formData.secondReminderDateTime
        form.selectFlight(candidate(arrival:"20:30",depTerminal:"1",arrTerminal:"B"))
        await form.flightTimeZoneTask?.value
        XCTAssertEqual(form.formData.appointmentTime,pickup)
        XCTAssertEqual(form.formData.reminderDateTime,first);XCTAssertEqual(form.formData.secondReminderDateTime,second)
        XCTAssertTrue(form.formData.reminderEnabled);XCTAssertTrue(form.formData.hasSecondReminder)
        XCTAssertEqual(form.formData.travelAgencyOrderNumber,"C-1234567-US")
        XCTAssertEqual(form.formData.flightEstimatedArrivalTime,"20:30")
        let saved=try JSONDecoder().decode(SavedFlightSelection.self,from:Data(form.formData.flightSelectionSnapshotJSON.utf8))
        XCTAssertEqual(saved.selected.departureTerminal,"1");XCTAssertEqual(saved.selected.arrivalTerminal,"B")
        XCTAssertEqual(saved.flightNumber,"JX2")
    }
    @MainActor func testReselectingSegmentDoesNotCarryPreviousTerminalsIntoSnapshot() async throws {
        let form=try draft()
        form.selectFlight(candidate(arrival:"20:30",depTerminal:"1",arrTerminal:"B"));await form.flightTimeZoneTask?.value
        form.selectFlight(candidate(arrival:"21:00",depTerminal:nil,arrTerminal:nil));await form.flightTimeZoneTask?.value
        let saved=try JSONDecoder().decode(SavedFlightSelection.self,from:Data(form.formData.flightSelectionSnapshotJSON.utf8))
        XCTAssertNil(saved.selected.departureTerminal);XCTAssertNil(saved.selected.arrivalTerminal)
        XCTAssertEqual(form.formData.flightArrivalTerminal,"")
        XCTAssertEqual(form.formData.flightEstimatedArrivalTime,"21:00")
    }
    @MainActor func testInvalidatingFlightClearsSnapshotButKeepsOrderAndPickupReminderPlan() async throws {
        let form=try draft()
        form.selectFlight(candidate(arrival:"20:30",depTerminal:"1",arrTerminal:"B"));await form.flightTimeZoneTask?.value
        let pickup=form.formData.appointmentTime,first=form.formData.reminderDateTime,second=form.formData.secondReminderDateTime
        form.changeNumber("JX4")
        XCTAssertEqual(form.formData.flightSelectionSnapshotJSON,"")
        XCTAssertEqual(form.formData.flightArrivalTerminal,"")
        XCTAssertEqual(form.formData.flightEstimatedArrivalTime,"")
        XCTAssertEqual(form.formData.travelAgencyOrderNumber,"C-1234567-US")
        XCTAssertEqual(form.formData.appointmentTime,pickup)
        XCTAssertEqual(form.formData.reminderDateTime,first);XCTAssertEqual(form.formData.secondReminderDateTime,second)
    }
}


final class PickupDateTimeBoundaryTests: XCTestCase {
    private let raw = """
    订单号：C-1234567-US
    接机日期：11/25 航班号：JX2，抵达机场：LAX
    接机时间：预计19:00 到达
    类型：接机
    客人地址：QA Hotel 住址：100 QA Street
    联络人：QA GUEST（3人）
    人数：3人，5件行李
    """
    private var now:Date { ISO8601DateFormatter().date(from:"2026-10-25T12:00:00Z")! }
    func testMonthDayYearKeepsExplicitPastYear() throws {
        let order=try XCTUnwrap(PickupOrderRecognizer.recognize(raw.replacingOccurrences(of:"11/25",with:"11/25/2025"),now:now))
        XCTAssertEqual(order.dateText,"2025-11-25");XCTAssertFalse(order.inferredYear)
    }
    func testMalformedTrailingYearIsNotSilentlyDropped() throws {
        let order=try XCTUnwrap(PickupOrderRecognizer.recognize(raw.replacingOccurrences(of:"11/25",with:"11/25/20270"),now:now))
        XCTAssertNil(order.date);XCTAssertNil(order.pickupDateTime)
    }
    func testExtraMinuteDigitsAreNotTruncatedToValidTime() throws {
        let order=try XCTUnwrap(PickupOrderRecognizer.recognize(raw.replacingOccurrences(of:"19:00",with:"19:000"),now:now))
        XCTAssertNil(order.estimatedArrival);XCTAssertNil(order.pickupDateTime)
    }
    func testNonexistentSpringClockTimeCannotBeApplied() throws {
        let value=raw.replacingOccurrences(of:"11/25",with:"2027/3/14").replacingOccurrences(of:"19:00",with:"02:30")
        let order=try XCTUnwrap(PickupOrderRecognizer.recognize(value,now:now))
        XCTAssertNotNil(order.date);XCTAssertNil(order.pickupDateTime)
        var form=NewTripFormModel();form.customerName="Keep draft";form.travelAgencyOrderNumber="Keep order"
        order.apply(to:&form,now:now)
        XCTAssertEqual(form.customerName,"Keep draft");XCTAssertEqual(form.travelAgencyOrderNumber,"Keep order")
    }
    func testMissingArrivalDoesNotPartiallyReplaceExistingDraft() throws {
        let value=raw.replacingOccurrences(of:"接机时间：预计19:00 到达",with:"")
        let order=try XCTUnwrap(PickupOrderRecognizer.recognize(value,now:now))
        var form=NewTripFormModel();form.customerName="Keep draft";form.travelAgencyOrderNumber="Keep order"
        let pickup=form.appointmentTime
        order.apply(to:&form,now:now)
        XCTAssertNil(order.pickupDateTime)
        XCTAssertEqual(form.customerName,"Keep draft");XCTAssertEqual(form.travelAgencyOrderNumber,"Keep order")
        XCTAssertEqual(form.appointmentTime,pickup)
    }
}


final class PickupBlankFieldBoundaryTests: XCTestCase {
    private let raw = """
    订单号：C-1234567-US
    接机日期：11/25
    航班号：JX2，抵达机场：LAX
    接机时间：预计19:00 到达
    类型：接机
    客人地址：QA Hotel 住址：100 QA Street
    联络人：QA GUEST
    联络电话：+886900000001
    人数：3人，5件行李
    """
    private var now:Date { ISO8601DateFormatter().date(from:"2026-10-25T12:00:00Z")! }
    func testEmptyContactDoesNotConsumeNextPhoneLabel() {
        XCTAssertNil(PickupOrderRecognizer.recognize(raw.replacingOccurrences(of:"联络人：QA GUEST",with:"联络人：   "),now:now))
    }
    func testEmptyAddressDoesNotConsumeNextContact() {
        XCTAssertNil(PickupOrderRecognizer.recognize(raw.replacingOccurrences(of:"客人地址：QA Hotel 住址：100 QA Street",with:"客人地址：   "),now:now))
    }
    func testEmptyDateDoesNotConsumeNextFlightLine() {
        XCTAssertNil(PickupOrderRecognizer.recognize(raw.replacingOccurrences(of:"接机日期：11/25",with:"接机日期：   "),now:now))
    }
    func testBlankPhoneDoesNotStealUnlabeledNumberFromNextLine() throws {
        let value=raw.replacingOccurrences(of:"联络电话：+886900000001",with:"联络电话：   \n+886900000002")
        let result=try XCTUnwrap(PickupOrderRecognizer.recognize(value,now:now))
        XCTAssertNil(result.phone)
    }
    func testBlankArrivalDoesNotStealClockFromNextLine() throws {
        let value=raw.replacingOccurrences(of:"接机时间：预计19:00 到达",with:"接机时间：   \n19:00")
        let result=try XCTUnwrap(PickupOrderRecognizer.recognize(value,now:now))
        XCTAssertNil(result.estimatedArrival);XCTAssertNil(result.pickupDateTime)
    }
    @MainActor func testMissingOptionalPhonePreservesManualContactInBothEditors() throws {
        let value=raw.replacingOccurrences(of:"联络电话：+886900000001",with:"")
        let result=try XCTUnwrap(PickupOrderRecognizer.recognize(value,now:now))
        var local=NewTripFormModel();local.custemerConnect="Manual contact"
        result.apply(to:&local,now:now)
        XCTAssertEqual(local.custemerConnect,"Manual contact")
        let cloud=CloudSmartInputHarness();cloud.customerContact="Manual contact"
        cloud.applyRecognizedOrder(result)
        XCTAssertEqual(cloud.customerContact,"Manual contact")
    }
}

final class NarrowCloudSettlementTests: XCTestCase {
    @MainActor private func run(rejected: Bool, switchAccount: Bool = false, duplicate: Bool = false, restart: Bool = false, markPaid: Bool = true, initiallyPaid: Bool = false) async throws {
        let owner="00000000-0000-0000-0000-000000000001",email="isolated-settlement@example.invalid"
        let auth=AuthViewModel(),oldScope=DataOwnership.activeScope
        var reads=0,writes=0
        var held: SyncFixtureProtocol?
        var heldSecond: SyncFixtureProtocol?
        let secondStarted = restart ? expectation(description:"New session settlement held") : nil
        let started = (switchAccount || duplicate) ? expectation(description:"Settlement request held") : nil
        let row:[String:Any] = ["id":"00000000-0000-0000-0000-000000000002","service_type":"接机","order_source":"旅行社订单",
            "travel_agency_code":"TF","travel_agency_name":"途风","travel_agency_order_number":"LATEST-ORDER",
            "customer_name":"QA","customer_contact":"fixture","customer_count":"3","customer_stuff":"5",
            "appointment_date":"2026-11-25T20:00:00Z","appointment_time":"2026-11-26T03:00:00Z",
            "location_start":"LAX","location_end":"New destination","flight_info":"JX2","flight_date":"2026-11-25T20:00:00Z",
            "flight_arrival_terminal":"B","memo":"Latest memo","price":80,"tip":0,"is_paid":initiallyPaid,"is_completed":true,"is_cancelled":false,
            "reminder_enabled":true,"has_second_reminder":true,"reminder_at":"2026-11-25T03:00:00Z","second_reminder_at":"2026-11-26T01:00:00Z",
            "currency_code":"USD","created_at":"2026-10-25T00:00:00Z"]
        let rows=String(decoding:try JSONSerialization.data(withJSONObject:[row]),as:UTF8.self)
        SyncFixtureProtocol.handle = { fixture in
            switch fixture.request.url!.path {
            case "/auth/v1/token": fixture.respond("{\"access_token\":\"fixture-only\",\"refresh_token\":\"fixture-refresh\",\"expires_in\":3600,\"user\":{\"email\":\"\(email)\"}}")
            case "/auth/v1/user": fixture.respond("{\"id\":\"\(owner)\",\"email\":\"\(email)\"}")
            case "/rest/v1/trips":
                XCTAssertEqual(fixture.request.httpMethod,"GET")
                reads += 1
                if reads==1 {fixture.respond(rows)} else {fixture.respond("{\"message\":\"Fixture refresh unavailable\"}",status:503)}
            case "/rest/v1/rpc/settle_online_trip", "/rest/v1/rpc/save_online_trip_finances":
                XCTAssertEqual(fixture.request.url!.lastPathComponent, markPaid ? "settle_online_trip" : "save_online_trip_finances")
                writes += 1
                var data=fixture.request.httpBody ?? Data()
                if data.isEmpty,let stream=fixture.request.httpBodyStream {
                    stream.open();defer{stream.close()};var buffer=[UInt8](repeating:0,count:4096)
                    while stream.hasBytesAvailable {let n=stream.read(&buffer,maxLength:buffer.count);if n<=0{break};data.append(contentsOf:buffer.prefix(n))}
                }
                let payload=try! JSONSerialization.jsonObject(with:data) as! [String:Any]
                XCTAssertEqual(Set(payload.keys),Set(["p_trip_id","p_fare","p_tip","p_expenses"]))
                XCTAssertEqual(payload["p_fare"] as? Double,(restart && writes == 2) ? 95:90);XCTAssertEqual(payload["p_tip"] as? Double,(restart && writes == 2) ? 6:5)
                if writes == 2, let secondStarted { heldSecond=fixture;secondStarted.fulfill() }
                else if let started { held=fixture;started.fulfill() }
                else { fixture.respond(rejected ? "{\"message\":\"Fixture settlement rejected\"}":"null",status:rejected ? 503:200) }
            case "/rest/v1/user_settings": fixture.respond("[{\"currency_code\":\"USD\"}]")
            default: fixture.respond("[]")
            }
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer{SyncFixtureProtocol.handle=nil;URLProtocol.unregisterClass(SyncFixtureProtocol.self);auth.clearIsolatedTestSession();DataOwnership.activateLocal(scope:oldScope)}
        let loginError=await auth.loginToCloud(email:email,password:"fixture-only")
        XCTAssertNil(loginError)
        let directory=CloudTripDirectoryModel();await directory.reloadTrips(using:auth)
        let id=try XCTUnwrap(directory.trips.first?.id)
        let expenses:[[String:Any]]=[["id":UUID().uuidString.lowercased(),"position":0,"is_addition":false,"title":"Parking","amount":2.0]]
        let task=Task { await directory.settle(id:id,fare:90,tip:5,expenses:expenses,markPaid:markPaid,using:auth) }
        if let started {
            await fulfillment(of:[started],timeout:3)
            XCTAssertTrue(directory.isSaving)
            if duplicate {
                let second=await directory.settle(id:id,fare:999,tip:99,expenses:[],using:auth)
                XCTAssertFalse(second);XCTAssertEqual(writes,1)
                XCTAssertTrue(directory.isSaving)
            }
            if switchAccount {
                auth.clearIsolatedTestSession();directory.clearForAccountChange()
                XCTAssertFalse(directory.isSaving)
                XCTAssertNil(directory.errorMessage)
            }
            if restart, let secondStarted {
                let loginError = await auth.loginToCloud(email:email,password:"fixture-only")
                XCTAssertNil(loginError)
                await directory.reloadTrips(using:auth)
                let fresh=Task {await directory.settle(id:id,fare:95,tip:6,expenses:expenses,using:auth)}
                await fulfillment(of:[secondStarted],timeout:3)
                held?.respond(rejected ? "{\"message\":\"Old request failed\"}":"null",status:rejected ? 503:200)
                let staleSaved=await task.value
                XCTAssertFalse(staleSaved)
                XCTAssertTrue(directory.isSaving,"Old completion must not release the newer request's busy state")
                XCTAssertNil(directory.errorMessage,"Old completion must not publish an error into the new request")
                heldSecond?.respond("null")
                let freshSaved=await fresh.value
                XCTAssertTrue(freshSaved);XCTAssertFalse(directory.isSaving);XCTAssertEqual(writes,2)
                return
            }
            held?.respond(rejected ? "{\"message\":\"Old request failed\"}":"null",status:rejected ? 503:200)
        }
        let saved=await task.value
        if switchAccount {
            XCTAssertFalse(saved);XCTAssertEqual(writes,1)
            XCTAssertTrue(directory.trips.isEmpty);XCTAssertFalse(directory.isSaving)
            XCTAssertNil(directory.errorMessage)
            return
        }
        XCTAssertEqual(saved,!rejected);XCTAssertEqual(writes,1);XCTAssertFalse(directory.isSaving)
        let cached=try XCTUnwrap(directory.trips.first)
        XCTAssertEqual(cached.price,rejected ? 80:90);XCTAssertEqual(cached.tip,rejected ? 0:5)
        XCTAssertEqual(cached.isPaid,initiallyPaid || (markPaid && !rejected));XCTAssertTrue(cached.isCompleted)
        XCTAssertEqual(cached.travelAgencyOrderNumber,"LATEST-ORDER");XCTAssertEqual(cached.flightArrivalTerminal,"B")
        XCTAssertEqual(cached.memo,"Latest memo");XCTAssertEqual(cached.locationEnd,"New destination")
        XCTAssertTrue(cached.reminderEnabled);XCTAssertTrue(cached.hasSecondReminder)
        XCTAssertEqual(cached.reminderAt,"2026-11-25T03:00:00Z");XCTAssertEqual(cached.secondReminderAt,"2026-11-26T01:00:00Z")
        XCTAssertEqual(cached.expenses.count,rejected ? 0:1)
    }
    @MainActor func testSaveOnlyUnpaidRetainsUnpaidAndUsesNarrowRPC() async throws { try await run(rejected:false,markPaid:false) }
    @MainActor func testSaveOnlyPaidRetainsPaid() async throws { try await run(rejected:false,markPaid:false,initiallyPaid:true) }
    @MainActor func testRejectedSaveOnlyRetainsFinancialState() async throws { try await run(rejected:true,markPaid:false) }
    @MainActor func testRejectedOldSettlementCannotPublishErrorAfterLogout() async throws {try await run(rejected:true,switchAccount:true)}
    @MainActor func testOldSettlementCannotReleaseOrReportIntoNewSessionRequest() async throws {try await run(rejected:false,switchAccount:true,restart:true)}
    @MainActor func testLateSettlementAfterLogoutCannotRepopulateAccountCache() async throws {try await run(rejected:false,switchAccount:true)}
    @MainActor func testConcurrentSecondSettlementIsRejectedWithoutAnotherRequest() async throws {try await run(rejected:false,duplicate:true)}
    @MainActor func testConfirmedSettlementOnlyChangesFinancialCacheWhenReloadFails() async throws {try await run(rejected:false)}
    @MainActor func testRejectedSettlementLeavesCachedFinancialAndUnrelatedFieldsUntouched() async throws {try await run(rejected:true)}
    @MainActor func testInvalidSettlementStopsBeforeAnyNetworkRequest() async {
        var requests=0
        SyncFixtureProtocol.handle={ fixture in requests += 1;fixture.respond("[]") }
        URLProtocol.registerClass(SyncFixtureProtocol.self)
        defer{SyncFixtureProtocol.handle=nil;URLProtocol.unregisterClass(SyncFixtureProtocol.self)}
        do {
            try await CloudOnlineRepository.saveSettlement(id:UUID().uuidString,fare:.nan,tip:0,expenses:[],account:.init(id:"fixture",email:"fixture@example.invalid"),accessToken:"fixture-only")
            XCTFail("Invalid fare must fail")
        } catch { XCTAssertEqual(requests,0) }
    }
    @MainActor func testSettlementEditorUsesNarrowRouteAndDismissesOnlyOnSuccess() async {
        let form=CloudSettlementRouteHarness();await form.save()
        XCTAssertEqual(form.directory.calls,1);XCTAssertTrue(form.dismissed);XCTAssertFalse(form.reachedFullSave)
        XCTAssertEqual(form.directory.savedFare,90);XCTAssertEqual(form.directory.savedTip,5)
        XCTAssertEqual(form.directory.savedExpenses.count,1)
    }
    @MainActor func testSettlementEditorFailureRetainsDraftAndDoesNotFallThroughToFullSave() async {
        let form=CloudSettlementRouteHarness();form.directory.succeeds=false
        await form.save()
        XCTAssertFalse(form.dismissed);XCTAssertFalse(form.reachedFullSave)
        XCTAssertEqual(form.price,"90");XCTAssertEqual(form.tip,"5");XCTAssertEqual(form.expenses.first?.title,"Parking")
        form.directory.succeeds=true;await form.save()
        XCTAssertEqual(form.directory.calls,2);XCTAssertTrue(form.dismissed)
    }
}


final class CloudDetailLatestExecutionStateTests: XCTestCase {
    private func snapshot() -> SavedFlightSelection {
        .init(flightNumber:"UA1743",flightDate:Date(timeIntervalSince1970:1792800000),selected:
            .init(airlineName:"Fixture",departureAirport:"IAH",arrivalAirport:"LAX",departureTerminal:"C",arrivalTerminal:"7",departureTime:"16:30",estimatedArrivalTime:"18:07",baggageCarousel:nil))
    }
    @MainActor func testRemoteRestoreAfterCompletionRefreshesDetailStatusAndFlightVisibility() async {
        let form=CloudTripDetailViewDisplayHarness()
        form.setSnapshot(snapshot())
        var cached=form.directory.trips[0];cached.isCompleted=true;form.directory.trips=[cached]
        form.refreshSavedFlightDisplay();await form.refreshTask?.value
        XCTAssertTrue(form.isCompleted);XCTAssertNil(form.flightLookupResult)
        cached.isCompleted=false;cached.isCancelled=false;form.directory.trips=[cached]
        form.refreshSavedFlightDisplay();await form.refreshTask?.value
        XCTAssertFalse(form.isCompleted);XCTAssertFalse(form.isCancelled)
        XCTAssertEqual(form.flightLookupResult?.arrivalTerminal,"7")
    }
    @MainActor func testRemoteCompletionAfterCancellationUsesLatestBothStatusFlags() async {
        let form=CloudTripDetailViewDisplayHarness()
        form.setSnapshot(snapshot())
        var cached=form.directory.trips[0];cached.isCancelled=true;form.directory.trips=[cached]
        form.refreshSavedFlightDisplay();await form.refreshTask?.value
        XCTAssertTrue(form.isCancelled);XCTAssertFalse(form.isCompleted);XCTAssertNil(form.flightLookupResult)
        cached.isCancelled=false;cached.isCompleted=true;form.directory.trips=[cached]
        form.refreshSavedFlightDisplay();await form.refreshTask?.value
        XCTAssertFalse(form.isCancelled);XCTAssertTrue(form.isCompleted);XCTAssertNil(form.flightLookupResult)
    }
}

final class RecognizedAgencyDirectoryMatchingTests: XCTestCase {
    private let raw = """
    订单号：C-1234567-US
    接机日期：11/25 航班号：JX2，抵达机场：LAX
    接机时间：预计19:00 到达
    类型：接机
    客人地址：QA Hotel 住址：100 QA Street
    联络人：QA GUEST（3人）
    联络电话：886-900000001
    人数：3人，5件行李
    """
    private func order() throws -> RecognizedPickupOrder {
        try XCTUnwrap(PickupOrderRecognizer.recognize(raw,now:ISO8601DateFormatter().date(from:"2026-10-26T12:00:00Z")!))
    }
    func testKnownTraditionalEnglishAndWidthAliasesButNotUnrelatedNames() {
        for value in ["途风", " 途風 ", "途風旅遊 (Tours4Fun)", "TOURS4FUN", "Ｔｏｕｒｓ４Ｆｕｎ"] {
            XCTAssertTrue(PickupAgencyMatcher.matches(value),value)
        }
        for value in ["途风合作二部", "途风2", "Other Tours", ""] {XCTAssertFalse(PickupAgencyMatcher.matches(value),value)}
    }
    @MainActor func testCloudMatchReturnsStoredAgencyCodeAndCanonicalNameWithoutReplacingGuestPhone() throws {
        let form=CloudSmartInputHarness()
        form.directory.agencies=[.init(name:"途風旅遊 (Tours4Fun)",agencyCode:"TF-REAL")]
        form.applyRecognizedOrder(try order())
        XCTAssertEqual(form.agencyCode,"TF-REAL");XCTAssertEqual(form.agencyName,"途風旅遊 (Tours4Fun)")
        XCTAssertEqual(form.customerContact,"+886900000001")
        XCTAssertEqual(form.agencyOrderNumber,"C-1234567-US")
    }
    @MainActor func testDirectoryShortTravelNameAndSpacedCodeArePreserved() throws {
        let form=CloudSmartInputHarness()
        form.directory.agencies=[.init(name:"途风旅行",agencyCode:"QA TF0001")]
        form.applyRecognizedOrder(try order())
        XCTAssertEqual(form.agencyName,"途风旅行")
        XCTAssertEqual(form.agencyCode,"QA TF0001")
    }
    @MainActor func testMultipleAliasMatchesRequireManualSelection() throws {
        let form=CloudSmartInputHarness()
        form.directory.agencies=[.init(name:"途风",agencyCode:"TF1"),.init(name:"Tours4Fun",agencyCode:"TF2")]
        form.applyRecognizedOrder(try order())
        XCTAssertEqual(form.agencyCode,"")
    }
    @MainActor func testBlankDirectoryCodeCannotBeAutoSelected() throws {
        let form=CloudSmartInputHarness()
        form.directory.agencies=[.init(name:"途风",agencyCode:"   ")]
        form.applyRecognizedOrder(try order())
        XCTAssertEqual(form.agencyCode,"")
    }
    @MainActor func testLocalDirectoryUsesOnlyActiveAccountAndStoredAgencyName() throws {
        let old=DataOwnership.activeScope
        DataOwnership.activateCloud(email:"isolated-agency-match@example.invalid")
        defer{DataOwnership.activateLocal(scope:old)}
        let schema=Schema(AppDataSchema.modelTypes)
        let container=try ModelContainer(for:schema,configurations:[ModelConfiguration(schema:schema,isStoredInMemoryOnly:true)])
        let context=ModelContext(container)
        let own=TravelAgency(agencyCode:"TF-LOCAL",name:"途風旅遊 (Tours4Fun)")
        own.ownerScope=DataOwnership.activeScope
        let other=TravelAgency(agencyCode:"OTHER-ACCOUNT",name:"途风")
        other.ownerScope="cloud:unrelated-fixture@example.invalid"
        context.insert(own);context.insert(other);try context.save()
        let form=LocalSmartInputHarness(context:context)
        form.applyRecognizedOrder(try order())
        XCTAssertEqual(form.formData.travelAgencyCode,"TF-LOCAL")
        XCTAssertEqual(form.formData.travelAgencyName,own.name)
        XCTAssertEqual(form.formData.custemerConnect,"+886900000001")
    }
}


private final class QAAddressCompleter: MKLocalSearchCompleter {
    var fragment = ""
    var cancelled = false
    var items: [MKLocalSearchCompletion] = []
    override var queryFragment: String { get { fragment } set { fragment = newValue } }
    override var results: [MKLocalSearchCompletion] { items }
    override func cancel() { cancelled = true }
}

@MainActor
final class AddressAutocompleteRegressionTests: XCTestCase {
    private func settle() async { try? await Task.sleep(for: .milliseconds(420)) }
    func testSameQueryAndClearRetypeKeepCachedCandidates() async {
        var requests: [QAAddressCompleter] = []
        let model = AddressAutocompleteSearcher(makeCompleter: { let c = QAAddressCompleter(); requests.append(c); return c })
        model.searchQuery = "LAX"; await settle()
        XCTAssertEqual(requests.count, 1)
        guard let first = requests.first else { return }
        first.items = [MKLocalSearchCompletion()]
        model.completerDidUpdateResults(first); await settle()
        XCTAssertEqual(model.completions.count, 1)
        model.searchQuery = "LAX"; await settle()
        XCTAssertEqual(model.completions.count, 1)
        XCTAssertEqual(requests.count, 1)
        model.searchQuery = ""; XCTAssertTrue(model.completions.isEmpty)
        model.searchQuery = "LAX"; await settle()
        XCTAssertEqual(model.completions.count, 1)
        XCTAssertEqual(requests.count, 1)
    }
    func testCancelledResponseCannotReplaceNewQuery() async {
        var requests: [QAAddressCompleter] = []
        let model = AddressAutocompleteSearcher(makeCompleter: { let c = QAAddressCompleter(); requests.append(c); return c })
        model.searchQuery = "LAX"; await settle()
        guard let old = requests.first else { XCTFail("Missing request"); return }
        model.searchQuery = "Pasadena"; await settle()
        XCTAssertTrue(old.cancelled)
        old.items = [MKLocalSearchCompletion()]
        model.completerDidUpdateResults(old); await settle()
        XCTAssertTrue(model.completions.isEmpty)
        XCTAssertTrue(model.isSearching)
        guard let current = requests.last else { return }
        current.items = [MKLocalSearchCompletion(), MKLocalSearchCompletion()]
        model.completerDidUpdateResults(current); await settle()
        XCTAssertEqual(model.completions.count, 2)
        XCTAssertFalse(model.isSearching)
    }
    func testFailedQueryCanRetryAndRecover() async {
        var requests: [QAAddressCompleter] = []
        let model = AddressAutocompleteSearcher(makeCompleter: { let c = QAAddressCompleter(); requests.append(c); return c })
        model.searchQuery = "LAX"; await settle()
        guard let failed = requests.first else { XCTFail("Missing request"); return }
        model.completer(failed, didFailWithError: NSError(domain: NSURLErrorDomain, code: -1009)); await settle()
        XCTAssertNotNil(model.errorMessage)
        model.retry()
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(model.errorMessage)
        guard let retry = requests.last else { return }
        retry.items = [MKLocalSearchCompletion()]
        model.completerDidUpdateResults(retry); await settle()
        XCTAssertEqual(model.completions.count, 1)
        XCTAssertFalse(model.isSearching)
    }

    func testClearedUnfinishedQueryRestartsWithFreshRequest() async {
        var requests: [QAAddressCompleter] = []
        let model = AddressAutocompleteSearcher(makeCompleter: { let c = QAAddressCompleter(); requests.append(c); return c })
        model.searchQuery = "LAX"; await settle()
        guard let cancelled = requests.first else { XCTFail("Missing request"); return }
        model.searchQuery = ""
        XCTAssertTrue(cancelled.cancelled)
        XCTAssertFalse(model.isSearching)
        model.searchQuery = "LAX"; await settle()
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(requests.last === cancelled)
        XCTAssertEqual(requests.last?.fragment, "LAX")
        XCTAssertTrue(model.isSearching)
    }
    func testWhitespaceInputDoesNotRequestAndClearsResults() async {
        var requests: [QAAddressCompleter] = []
        let model = AddressAutocompleteSearcher(makeCompleter: { let c = QAAddressCompleter(); requests.append(c); return c })
        model.searchQuery = "  \n"; await settle()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(model.isSearching)
        model.searchQuery = " LAX "; await settle()
        XCTAssertEqual(requests.first?.fragment, "LAX")
        guard let request = requests.first else { XCTFail("Missing request"); return }
        request.items = [MKLocalSearchCompletion()]
        model.completerDidUpdateResults(request); await settle()
        model.searchQuery = " \n "
        XCTAssertTrue(model.completions.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isSearching)
    }
    func testOldFailureCannotReplaceSuccessfulNewQuery() async {
        var requests: [QAAddressCompleter] = []
        let model = AddressAutocompleteSearcher(makeCompleter: { let c = QAAddressCompleter(); requests.append(c); return c })
        model.searchQuery = "LAX"; await settle()
        guard let old = requests.first else { XCTFail("Missing request"); return }
        model.searchQuery = "Pasadena"; await settle()
        guard let current = requests.last else { return }
        current.items = [MKLocalSearchCompletion()]
        model.completerDidUpdateResults(current); await settle()
        model.completer(old, didFailWithError: NSError(domain: NSURLErrorDomain, code: -1009)); await settle()
        XCTAssertEqual(model.completions.count, 1)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isSearching)
    }
    func testRegionChangeInvalidatesCachedResultsAndRejectsOldResponse() async {
        var requests: [QAAddressCompleter] = []
        let model = AddressAutocompleteSearcher(makeCompleter: { let c = QAAddressCompleter(); requests.append(c); return c })
        model.searchQuery = "LAX"; await settle()
        guard let old = requests.first else { XCTFail("Missing request"); return }
        old.items = [MKLocalSearchCompletion()]
        model.completerDidUpdateResults(old); await settle()
        let center = CLLocationCoordinate2D(latitude: 34.05, longitude: -118.25)
        model.updateRegion(center: center)
        XCTAssertTrue(model.completions.isEmpty)
        XCTAssertTrue(model.isSearching)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last!.region.center.latitude, center.latitude, accuracy: 0.001)
        model.completerDidUpdateResults(old); await settle()
        XCTAssertTrue(model.completions.isEmpty)
        guard let current = requests.last else { return }
        current.items = [MKLocalSearchCompletion(), MKLocalSearchCompletion()]
        model.completerDidUpdateResults(current); await settle()
        XCTAssertEqual(model.completions.count, 2)
    }
}

final class FinanceCancellationPolicyTests: XCTestCase {
    @MainActor func testCancelledFareTipAndExpensesAreExcludedFromAllPeriodRecords() {
        let start = Date(timeIntervalSince1970: 1_000), end = Date(timeIntervalSince1970: 2_000)
        let interval = DateInterval(start: start, end: end)
        let rows: [(cancelled: Bool, date: Date?, fare: Double, tip: Double, expense: Double)] = [
            (false, start, 90, 10, 5), (true, start, 50, 20, 8),
            (false, end, 200, 0, 0), (false, nil, 300, 0, 0)
        ]
        let selected = rows.filter { FinancialTripInclusion.includes(cancelled: $0.cancelled, date: $0.date, in: interval) }
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.reduce(0) { $0 + $1.fare + $1.tip - $1.expense }, 95)
        XCTAssertFalse(FinancialTripInclusion.includes(cancelled: false, date: start.addingTimeInterval(-1), in: interval))
    }
}

final class FinanceSaveOnlyLocalTests: XCTestCase {
    @MainActor func testSaveOnlyPreservesBothPaymentStatesAndUnrelatedFields() throws {
        for paid in [false,true] {
            let booking = TripBookingRecord(form: NewTripFormModel())
            booking.isPaid=paid; booking.isCompleted=true;booking.locationStart="Keep route";booking.memo="Keep note"
            try SettlementValidation.save(booking:booking,fare:120,tip:8,expenses:[.init(isAddition:false,title:"Toll",amount:5)],markPaid:false) {}
            XCTAssertEqual(booking.price,120);XCTAssertEqual(booking.tip,8);XCTAssertEqual(booking.isPaid,paid)
            XCTAssertTrue(booking.isCompleted);XCTAssertEqual(booking.locationStart,"Keep route");XCTAssertEqual(booking.memo,"Keep note")
        }
    }
    @MainActor func testSaveOnlyFailureRestoresMoneyAndPaymentState() throws {
        struct DiskFailure: Error {}
        let booking = TripBookingRecord(form:NewTripFormModel());booking.price=90;booking.tip=5;booking.isPaid=false
        XCTAssertThrowsError(try SettlementValidation.save(booking:booking,fare:120,tip:8,expenses:[],markPaid:false) { throw DiskFailure() })
        XCTAssertEqual(booking.price,90);XCTAssertEqual(booking.tip,5);XCTAssertFalse(booking.isPaid)
    }
    @MainActor func testCloudEditorSaveOnlyRoutesWithoutMarkingPaid() async {
        let form=CloudSettlementRouteHarness();await form.save(markPaid:false)
        XCTAssertEqual(form.directory.calls,1);XCTAssertFalse(form.directory.savedMarkPaid);XCTAssertTrue(form.dismissed);XCTAssertFalse(form.reachedFullSave)
    }
}

final class FlightNumberKeyboardTests: XCTestCase {
    @MainActor func testLettersNumbersSelectionAndBackspaceUpdateBinding() throws {
        var stored = "MU2018"
        let coordinator = FlightNumberTextField.Coordinator(text: Binding(get: { stored }, set: { stored = $0 }))
        let field = UITextField()
        field.text = stored
        coordinator.textField = field
        func select(_ start: Int, _ end: Int) throws {
            let a = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: start))
            let b = try XCTUnwrap(field.position(from: field.beginningOfDocument, offset: end))
            field.selectedTextRange = field.textRange(from: a, to: b)
        }
        func press(_ key: String) {
            let button = UIButton(type: .system); button.setTitle(key, for: .normal)
            coordinator.pressFlightKey(button)
        }
        try select(0, 2); press("U"); press("A")
        XCTAssertEqual(stored, "UA2018")
        try select(2, 6); press("1"); press("7"); press("4"); press("3")
        XCTAssertEqual(stored, "UA1743")
        press("⌫"); XCTAssertEqual(stored, "UA174")
        try select(0, 2); press("⌫"); XCTAssertEqual(stored, "174")
        try select(0, 0); press("⌫"); XCTAssertEqual(stored, "174")
        press("⌄"); XCTAssertEqual(stored, "174")
    }
    @MainActor func testNarrowKeyboardKeepsEveryKeyWithinHorizontalSafeArea() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        let controller = UIViewController()
        window.rootViewController = controller
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 40, bottom: 0, right: 20)
        let keyboard = FlightNumberTextField.makeFlightKeyboard(target: .init(text: .constant("")))
        controller.view.addSubview(keyboard)
        keyboard.frame = CGRect(x: 0, y: 308, width: 320, height: 260)
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded(); controller.view.layoutIfNeeded(); keyboard.layoutIfNeeded()
        func buttons(_ view: UIView) -> [UIButton] { view.subviews.flatMap { child in (child as? UIButton).map { [$0] } ?? buttons(child) } }
        let safe = keyboard.safeAreaLayoutGuide.layoutFrame
        XCTAssertGreaterThanOrEqual(safe.minX, 40)
        for button in buttons(keyboard) {
            let frame = button.convert(button.bounds, to: keyboard)
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)
            XCTAssertGreaterThanOrEqual(frame.minX, safe.minX)
            XCTAssertLessThanOrEqual(frame.maxX, safe.maxX)
        }
    }
    @MainActor func testKeyboardContainsEveryDigitAndUppercaseLetterExactlyOnce() {
        let coordinator = FlightNumberTextField.Coordinator(text: .constant(""))
        let keyboard = FlightNumberTextField.makeFlightKeyboard(target: coordinator)
        func buttons(_ view: UIView) -> [UIButton] { view.subviews.flatMap { child in (child as? UIButton).map { [$0] } ?? buttons(child) } }
        let titles = buttons(keyboard).compactMap { $0.title(for: .normal) }
        XCTAssertEqual(titles.count, 38)
        for key in "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" { XCTAssertEqual(titles.filter { $0 == String(key) }.count, 1) }
        XCTAssertTrue(titles.contains("⌫")); XCTAssertTrue(titles.contains("⌄"))
    }
}

final class TripReminderMessageTests: XCTestCase {
    func testMissingDepartureTerminalDoesNotBorrowArrivalAndLongAddressStaysInBody() {
        let now = Date()
        let flight = VariFlightLookupResult(airlineName: "QA", departureAirport: "HKG", arrivalAirport: "LAX", departureTerminal: nil, arrivalTerminal: "TBIT", departureTime: nil, estimatedArrivalTime: nil, baggageCarousel: nil)
        let address = "QA Hotel, 928 E Colorado Blvd #101, Pasadena, CA 91106"
        let message = TripReminderMessage(serviceType: "接机", flightNumber: "CX882", flight: flight, customer: " QA\nGuest ", start: "LAX\nTerminal B", end: address, appointmentDate: now, appointmentTime: now, locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(message.title, "行程管家")
        XCTAssertFalse(message.title.contains(address))
        let body = message.body(at: now)
        XCTAssertTrue(body.contains(address)); XCTAssertTrue(body.contains("QA Guest")); XCTAssertTrue(body.contains("LAX Terminal B")); XCTAssertFalse(body.contains("\n")); XCTAssertTrue(body.contains("CX882"))
    }
    func testChangedFlightContextCannotLeakOldTerminalsIntoReminder() {
        let now = Date()
        let oldFlight = VariFlightLookupResult(airlineName: "QA", departureAirport: "HKG", arrivalAirport: "LAX", departureTerminal: "1", arrivalTerminal: "TBIT", departureTime: nil, estimatedArrivalTime: nil, baggageCarousel: nil)
        let snapshot = SavedFlightSelection(flightNumber: "CX882", flightDate: now, selected: oldFlight)
        let context = SavedFlightDisplayContext(flightNumber: "JX2", flightDate: now, serviceType: "接机", locationStart: "LAX", locationEnd: "QA Hotel", snapshot: snapshot, canDisplay: true)
        XCTAssertNil(context.selection)
        let message = TripReminderMessage(serviceType: "接机", flightNumber: "JX2", flight: context.selection, customer: "QA", start: "LAX", end: "QA Hotel", appointmentDate: now, appointmentTime: now, locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(message.title, "行程管家")
        XCTAssertFalse(message.title.contains("TBIT")); XCTAssertFalse(message.title.contains("HKG"))
    }

    func testFlightTerminalsPickupDateAndRelativeTimeRemainSeparate() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 25))!
        let time = calendar.date(from: DateComponents(year: 2020, month: 1, day: 1, hour: 16, minute: 30))!
        let flight = VariFlightLookupResult(airlineName: "QA", departureAirport: "香港", arrivalAirport: "洛杉矶", departureTerminal: "1", arrivalTerminal: "TBIT", departureTime: "19:50", estimatedArrivalTime: "17:30", baggageCarousel: nil)
        let message = TripReminderMessage(serviceType: "接机", flightNumber: "cx882", flight: flight, customer: "QA Guest", start: "LAX", end: "QA Hotel", appointmentDate: day, appointmentTime: time, locale: Locale(identifier: "zh-Hans"), calendar: calendar)
        XCTAssertEqual(message.title, "行程管家")
        let body = message.body(at: message.pickup.addingTimeInterval(-52 * 60))
        XCTAssertTrue(body.contains("11/25 16:30")); XCTAssertTrue(body.contains("QA Guest")); XCTAssertTrue(body.contains("LAX → QA Hotel")); XCTAssertTrue(body.contains("52"))
        XCTAssertFalse(body.contains("17:30"))
        XCTAssertTrue(message.body(at: message.pickup.addingTimeInterval(-7200)).contains("2 小时"))
    }
    func testMissingFlightAndPastPickupHaveCleanFallbacks() {
        let now = Date()
        let message = TripReminderMessage(serviceType: "包车", flightNumber: "", flight: nil, customer: "", start: "QA Start", end: "QA End", appointmentDate: now, appointmentTime: now, locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(message.title, "行程管家")
        let body = message.body(at: now.addingTimeInterval(3600))
        XCTAssertTrue(body.contains("QA Start → QA End")); XCTAssertFalse(body.contains("距接客")); XCTAssertFalse(body.contains("nil"))
    }
}

final class CloudRegistrationFlowTests: XCTestCase {
    @MainActor func testSignupRequiresVerificationAndDoesNotStoreReturnedSession() async throws {
        let auth = AuthViewModel(); auth.clearIsolatedTestSession()
        let oldScope = DataOwnership.activeScope
        var calls = 0
        SyncFixtureProtocol.handle = { fixture in
            calls += 1
            XCTAssertEqual(fixture.request.url?.path, "/auth/v1/signup")
            let query = URLComponents(url: fixture.request.url!, resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertEqual(query?.first(where: { $0.name == "redirect_to" })?.value, "https://trvelma.pages.dev/")
            fixture.respond("{\"access_token\":\"fixture-only-access\",\"refresh_token\":\"fixture-only-refresh\",\"user\":{\"email\":\"qa-signup@example.invalid\"}}")
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer { auth.clearIsolatedTestSession(); DataOwnership.activateLocal(scope: oldScope); SyncFixtureProtocol.handle=nil; URLProtocol.unregisterClass(SyncFixtureProtocol.self) }
        let message = await auth.registerCloud(email: "QA-SIGNUP@example.invalid", salutation: "QA", phone: "", password: "fixture-only-strong")
        XCTAssertNotNil(message); XCTAssertEqual(calls, 1)
        XCTAssertFalse(auth.isLoggedIn); XCTAssertNil(auth.cloudAccessToken)
    }
    @MainActor func testSignupRejectsShortPasswordBeforeNetwork() async {
        let auth = AuthViewModel(); auth.clearIsolatedTestSession()
        let message = await auth.registerCloud(email: "qa@example.invalid", salutation: "QA", phone: "", password: "short")
        XCTAssertNotNil(message); XCTAssertFalse(auth.isLoggedIn)
    }
    @MainActor func testResendUsesSignupTypeWithoutPassword() async throws {
        SyncFixtureProtocol.handle = { fixture in
            XCTAssertEqual(fixture.request.url?.path, "/auth/v1/resend")
            var payload = fixture.request.httpBody ?? Data()
            if payload.isEmpty, let stream = fixture.request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; payload.append(buffer, count: count) }
            }
            let body = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
            XCTAssertEqual(body["type"] as? String, "signup")
            XCTAssertNil(body["password"])
            fixture.respond("{}")
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer { SyncFixtureProtocol.handle=nil; URLProtocol.unregisterClass(SyncFixtureProtocol.self) }
        try await SupabaseAuthClient.resendSignupConfirmation(email: "qa@example.invalid")
    }
}

final class StoreProductPolicyTests: XCTestCase {
    func testLocalNonConsumableHasNoExpiryButRevocationRemovesIt() {
        XCTAssertTrue(StoreProductCatalog.isActive(productID: StoreProductCatalog.local, revokedAt: nil, expiresAt: nil, upgraded: false))
        XCTAssertFalse(StoreProductCatalog.isActive(productID: StoreProductCatalog.local, revokedAt: .now, expiresAt: nil, upgraded: false))
    }
    func testSubscriptionRequiresFutureExpiryAndIgnoresUpgradedTransactions() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(StoreProductCatalog.isActive(productID: StoreProductCatalog.monthly, revokedAt: nil, expiresAt: now.addingTimeInterval(60), upgraded: false, now: now))
        XCTAssertFalse(StoreProductCatalog.isActive(productID: StoreProductCatalog.monthly, revokedAt: nil, expiresAt: nil, upgraded: false, now: now))
        XCTAssertFalse(StoreProductCatalog.isActive(productID: StoreProductCatalog.yearly, revokedAt: nil, expiresAt: now, upgraded: false, now: now))
        XCTAssertFalse(StoreProductCatalog.isActive(productID: StoreProductCatalog.monthly, revokedAt: nil, expiresAt: now.addingTimeInterval(60), upgraded: true, now: now))
    }
    func testUnknownProductCannotGrantEntitlement() {
        XCTAssertFalse(StoreProductCatalog.isActive(productID: "qa.unknown", revokedAt: nil, expiresAt: nil, upgraded: false))
    }
    @MainActor func testProductionSalesDefaultClosed() {
        XCTAssertFalse(StorePurchaseManager().salesEnabled)
    }
}

@MainActor
final class AgencyStatementExportTests: XCTestCase {
    func testPDFAndCSVExportAreRealFilesAndPaginateWithoutChangingRows() throws {
        let rows = (0..<35).map { index in
            AgencyStatementRow(id: "qa-\(index)", agencyCode: "QA", agencyName: "测试旅行社", date: Date(timeIntervalSince1970: 1793520000), time: .now,
                order: "QA-\(index)", service: "接机", guest: "测试客人", contact: "QA", route: "LAX → Pasadena Hotel & Pool", memo: "合成数据", passengers: "3", fare: 100, tip: 99, currency: "USD",
                fees: [.init(title: "停车费", amount: -11, addition: false), .init(title: "打印费", amount: 3, addition: true)])
        }
        let snapshot = AgencyStatementSnapshot(rows: rows)
        let pdf = try snapshot.exportFile(pdf: true)
        let csv = try snapshot.exportFile(pdf: false)
        let data = try Data(contentsOf: pdf)
        XCTAssertTrue(data.starts(with: Data("%PDF-".utf8)))
        let document = try XCTUnwrap(CGPDFDocument(pdf as CFURL))
        XCTAssertGreaterThan(document.numberOfPages, 1)
        XCTAssertTrue(try String(contentsOf: csv, encoding: .utf8).contains("$114.00"))
        XCTAssertEqual(snapshot.rows[0].tip,99)
        XCTAssertFalse(snapshot.headers.contains("小费"))
        let preview = FileManager.default.temporaryDirectory.appendingPathComponent("trvelma-statement-share-qa.pdf")
        try data.write(to: preview)
        print("STATEMENT_PDF_QA=\(preview.path)")
        // Verify every rendered page can be rasterized by Core Graphics.
        for index in 1...document.numberOfPages {
            let page = try XCTUnwrap(document.page(at: index))
            let bounds = page.getBoxRect(.mediaBox)
            let context = try XCTUnwrap(CGContext(data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8,
                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(UIColor.white.cgColor); context.fill(bounds); context.drawPDFPage(page)
            XCTAssertNotNil(context.makeImage())
        }
    }
}


final class FinancialCategoryAggregationTests: XCTestCase {
    func testSameTitleMergesAcrossIncomeAndExpenseWithoutChangingSignedTotals() {
        let rows = FinancialCategoryAggregation.groups([
            .init(title: "停车费", amount: 11, isAddition: false),
            .init(title: "停车费", amount: 3, isAddition: true),
            .init(title: "停车费", amount: 2, isAddition: false)
        ], fallback: "其他")
        XCTAssertEqual(rows.count,1)
        XCTAssertEqual(rows[0].income,3)
        XCTAssertEqual(rows[0].expense,13)
        XCTAssertEqual(rows[0].amount,16)
    }
    func testWhitespaceAndUnicodeEquivalentNamesShareOneGroup() {
        let rows = FinancialCategoryAggregation.groups([
            .init(title: "  Parking  fee\n", amount: 2, isAddition: false),
            .init(title: "Parking\tfee", amount: 3, isAddition: false),
            .init(title: "Café", amount: 4, isAddition: false),
            .init(title: "Cafe\u{301}", amount: 1, isAddition: false)
        ], fallback: "其他")
        XCTAssertEqual(rows.count,2)
        XCTAssertEqual(rows.map(\.amount).sorted(),[5,5])
    }
    func testEmptyNameAndInvalidOrZeroAmounts() {
        let rows = FinancialCategoryAggregation.groups([
            .init(title: " \n", amount: 2, isAddition: false),
            .init(title: "其他", amount: 3, isAddition: true),
            .init(title: "无效", amount: .nan, isAddition: true),
            .init(title: "零", amount: 0, isAddition: false)
        ], fallback: "其他")
        XCTAssertEqual(rows.count,1)
        XCTAssertEqual(rows[0].title,"其他")
        XCTAssertEqual(rows[0].income,3)
        XCTAssertEqual(rows[0].expense,2)
    }
}


final class LocalPlanFlightAccessTests: XCTestCase {
    @MainActor func testLocalLookupRejectsBeforeAnyNetworkRequest() async throws {
        var calls = 0
        SyncFixtureProtocol.handle = { request in
            calls += 1
            request.respond("{}")
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer { SyncFixtureProtocol.handle = nil; URLProtocol.unregisterClass(SyncFixtureProtocol.self) }
        do {
            _ = try await VariFlightClient().lookupCandidates(flightNumber: "UA1743", flightDate: .now)
            XCTFail("Local lookup must be denied")
        } catch VariFlightClientError.cloudEditionRequired { }
        XCTAssertEqual(calls, 0)
    }

    @MainActor func testEmptyCloudTokenCannotFallBackToLocalAPI() async throws {
        var calls = 0
        SyncFixtureProtocol.handle = { request in calls += 1; request.respond("{}") }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer { SyncFixtureProtocol.handle = nil; URLProtocol.unregisterClass(SyncFixtureProtocol.self) }
        do {
            _ = try await VariFlightClient().lookupCandidates(flightNumber: "UA1743", flightDate: .now, cloudAccessToken: "  ")
            XCTFail("Empty token must be denied")
        } catch VariFlightClientError.missingCloudSession { }
        XCTAssertEqual(calls, 0)
    }
}


final class StoreBillingTransportTests: XCTestCase {
    @MainActor func testCloudPurchaseSendsOnlySignedTransactionWithCurrentSession() async throws {
        var calls = 0
        SyncFixtureProtocol.handle = { request in
            calls += 1
            XCTAssertEqual(request.request.url?.path, "/functions/v1/storekit-verify")
            XCTAssertEqual(request.request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-only")
            var data = request.request.httpBody ?? Data()
            if data.isEmpty, let stream = request.request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 2048)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            do {
                let body = try JSONSerialization.jsonObject(with: data) as? [String: String]
                XCTAssertEqual(body, ["signedTransaction": "signed-fixture"])
            } catch { XCTFail("Invalid purchase request body") }
            request.respond("{\"recorded\":true}")
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer { SyncFixtureProtocol.handle = nil; URLProtocol.unregisterClass(SyncFixtureProtocol.self) }
        try await SupabaseAuthClient.verifyCloudStoreTransaction(accessToken: "fixture-only", signedTransaction: "signed-fixture")
        XCTAssertEqual(calls, 1)
    }

    @MainActor func testIgnoredDeletedAccountPurchaseIsNotReportedAsDelivered() async throws {
        SyncFixtureProtocol.handle = { request in
            request.respond("{\"recorded\":false,\"ignored\":\"ACCOUNT_DELETED\"}")
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer { SyncFixtureProtocol.handle = nil; URLProtocol.unregisterClass(SyncFixtureProtocol.self) }
        do {
            try await SupabaseAuthClient.verifyCloudStoreTransaction(accessToken: "fixture-only", signedTransaction: "signed-fixture")
            XCTFail("An ignored purchase must not finish delivery as a paid entitlement")
        } catch { /* Fail closed: no successful delivery is returned to StorePurchaseManager. */ }
    }

    @MainActor func testAccountTokenComesFromAuthenticatedServerUser() async throws {
        let expected = UUID()
        SyncFixtureProtocol.handle = { request in
            XCTAssertEqual(request.request.url?.path, "/auth/v1/user")
            XCTAssertEqual(request.request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-only")
            request.respond("{\"id\":\"\(expected.uuidString)\",\"email\":\"review@example.invalid\"}")
        }
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        defer { SyncFixtureProtocol.handle = nil; URLProtocol.unregisterClass(SyncFixtureProtocol.self) }
        let account = try await SupabaseAuthClient.fetchPurchaseAccount(accessToken: "fixture-only")
        XCTAssertEqual(account.id, expected)
        XCTAssertEqual(account.email, "review@example.invalid")
    }
}

final class TripTelephoneContactTests: XCTestCase {
    func testInternationalNumbersRemainDialableWithoutTreatingAccountsAsPhoneNumbers() {
        XCTAssertEqual(TripPhoneContact.number("+1 (909) 996-8379"), "+19099968379")
        XCTAssertEqual(TripPhoneContact.number("886-953341193"), "886953341193")
        for invalid in ["wechat123456", "a@example.com", "123", "1+23456789", "++12345678", "123456;call=1"] {
            XCTAssertNil(TripPhoneContact.number(invalid))
        }
    }
    func testOnlyTypedTelephoneContactsAreShownAndDuplicatesAreCollapsed() {
        XCTAssertEqual(TripPhoneContact.phones([("微信", "12345678"), ("邮箱", "a@example.com"), ("电话", "+1 (555) 000-0100"), ("电话", "+15550000100"), ("電話", "886-953341193")]), ["+1 (555) 000-0100", "886-953341193"])
    }
    @MainActor func testLinkedCustomerPhoneWinsOverTripWeChatSnapshotAndStaysWithinOwner() throws {
        let schema = Schema(AppDataSchema.modelTypes)
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let customer = Custumer(name: "QA Phone", email: "qa@example.invalid", csource: "", type: 1)
        customer.ownerScope = "phone-test-owner"
        customer.connecttype = [Connect(connectlable: "电话", connecttype: "+1 5550000100", customer: customer)]
        container.mainContext.insert(customer)
        let booking = TripBookingRecord(form: NewTripFormModel())
        booking.ownerScope = customer.ownerScope; booking.customerUUID = customer.uuid; booking.customerContact = "WeChat-QA"
        XCTAssertEqual(TripPhoneContact.local(booking, context: container.mainContext), ["+1 5550000100"])
        booking.ownerScope = "other-owner"
        XCTAssertEqual(TripPhoneContact.local(booking, context: container.mainContext), [])
    }
}

final class ExpiredArchiveRefreshRegressionTests: XCTestCase {
    private let data = Data(#"{"read_only":true,"customers":[{"name":"QA"}]}"#.utf8)
    func testTransientRefreshKeepsVisibleArchiveButBlocksExportUntilSuccess() throws {
        var state = ExpiredArchiveReadState()
        let first = state.begin(owner: "one"); try state.accept(data, request: first, owner: "one")
        XCTAssertTrue(state.canExport)
        let retry = state.begin(owner: "one")
        XCTAssertEqual((state.snapshot["customers"] as? [[String: Any]])?.count, 1)
        state.fail(request: retry, owner: "one", transient: true)
        XCTAssertEqual((state.snapshot["customers"] as? [[String: Any]])?.count, 1)
        XCTAssertFalse(state.canExport)
        let next = state.begin(owner: "one"); try state.accept(data, request: next, owner: "one")
        XCTAssertTrue(state.canExport)
    }
    func testPermissionFailureClearsArchiveAndCannotExport() throws {
        var state = ExpiredArchiveReadState()
        let first = state.begin(owner: "one"); try state.accept(data, request: first, owner: "one")
        let denied = state.begin(owner: "one"); state.fail(request: denied, owner: "one", transient: false)
        XCTAssertTrue(state.snapshot.isEmpty); XCTAssertTrue(state.exportData.isEmpty); XCTAssertFalse(state.canExport)
    }
    func testAccountSwitchAndLogoutRejectLateResponsesIncludingSameOwnerLogin() throws {
        var state = ExpiredArchiveReadState()
        let old = state.begin(owner: "one"); let newer = state.begin(owner: "two")
        try state.accept(data, request: old, owner: "one")
        XCTAssertTrue(state.snapshot.isEmpty); XCTAssertTrue(state.busy)
        try state.accept(data, request: newer, owner: "two"); state.reset()
        let current = state.begin(owner: "two")
        try state.accept(data, request: newer, owner: "two")
        XCTAssertTrue(state.snapshot.isEmpty)
        try state.accept(data, request: current, owner: "two"); XCTAssertTrue(state.canExport)
    }
    func testAuthoritativeEmptyRefreshReplacesOldRecordsAndOwnerSwitchClearsImmediately() throws {
        var state = ExpiredArchiveReadState()
        let first = state.begin(owner: "one"); try state.accept(data, request: first, owner: "one")
        let next = state.begin(owner: "one")
        try state.accept(Data(#"{"read_only":true,"customers":[]}"#.utf8), request: next, owner: "one")
        XCTAssertEqual((state.snapshot["customers"] as? [[String: Any]])?.count, 0)
        XCTAssertTrue(state.canExport)
        _ = state.begin(owner: "two")
        XCTAssertTrue(state.snapshot.isEmpty); XCTAssertTrue(state.exportData.isEmpty); XCTAssertFalse(state.canExport)
    }
    func testMalformedOrNonReadOnlyPayloadNeverReplacesVerifiedArchive() throws {
        var state = ExpiredArchiveReadState()
        let first = state.begin(owner: "one"); try state.accept(data, request: first, owner: "one")
        let bad = state.begin(owner: "one")
        XCTAssertThrowsError(try state.accept(Data(#"{"read_only":false}"#.utf8), request: bad, owner: "one"))
        state.fail(request: bad, owner: "one", transient: false)
        XCTAssertTrue(state.snapshot.isEmpty); XCTAssertFalse(state.canExport)
    }
}

final class SandboxRefundSelectionTests: XCTestCase {
    private let owner = SandboxRefundPolicy.lifecycleOwner
    private func permits(build: Bool = true, owner: UUID? = SandboxRefundPolicy.lifecycleOwner,
                         token: UUID? = SandboxRefundPolicy.lifecycleOwner, product: String = StoreProductCatalog.monthly,
                         environment: AppStore.Environment = .sandbox, revoked: Bool = false, upgraded: Bool = false) -> Bool {
        SandboxRefundPolicy.permits(buildEnabled: build, owner: owner, transactionOwner: token,
                                   product: product, environment: environment, revoked: revoked, upgraded: upgraded)
    }
    func testOnlyLifecycleOwnerAndMatchingTransactionAreEligible() {
        XCTAssertTrue(permits()); XCTAssertFalse(permits(owner: UUID())); XCTAssertFalse(permits(token: UUID()))
        XCTAssertFalse(permits(owner: nil)); XCTAssertFalse(permits(token: nil))
    }
    func testProductionAndXcodeTransactionsCannotBeRefundedFromSandboxEntry() {
        XCTAssertFalse(permits(environment: .production)); XCTAssertFalse(permits(environment: .xcode))
    }
    func testNormalBuildAndUnrelatedProductsCannotUseEntry() {
        XCTAssertFalse(permits(build: false)); XCTAssertFalse(permits(product: StoreProductCatalog.local))
        XCTAssertFalse(permits(product: "other.product"))
    }
    func testRevokedAndUpgradedPeriodsAreNotOfferedAgain() {
        XCTAssertFalse(permits(revoked: true)); XCTAssertFalse(permits(upgraded: true))
        XCTAssertTrue(permits(product: StoreProductCatalog.yearly))
    }
}

final class TripPeriodFilteringTests: XCTestCase {
    func testQuickOptionsDoNotDuplicateExistingAllEntry() {
        XCTAssertEqual(TripDateMode.quickOptions, [.day, .week, .month, .year])
        XCTAssertFalse(TripDateMode.quickOptions.contains(.all))
    }

    func testAllDoesNotRestrictTheListToItsTodayAnchor() {
        let anchor = date(2026, 11, 16)
        XCTAssertTrue(TripDateMode.all.includes(date(2025, 1, 1), anchor: anchor, calendar: calendar))
        XCTAssertTrue(TripDateMode.all.includes(date(2027, 12, 31), anchor: anchor, calendar: calendar))
        XCTAssertEqual(TripDateMode.all.component, .day)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
    func testDayUsesLocalCalendarAndExclusiveEnd() {
        let anchor = date(2026, 11, 16)
        XCTAssertTrue(TripDateMode.day.includes(date(2026, 11, 16, 0), anchor: anchor, calendar: calendar))
        XCTAssertFalse(TripDateMode.day.includes(date(2026, 11, 15, 23), anchor: anchor, calendar: calendar))
        XCTAssertFalse(TripDateMode.day.includes(date(2026, 11, 17, 0), anchor: anchor, calendar: calendar))
    }
    func testSundayStillBelongsToMondayWeekAcrossYearBoundary() {
        let anchor = date(2027, 1, 3)
        let range = TripDateMode.week.interval(anchor: anchor, calendar: calendar)
        XCTAssertEqual(range.start, date(2026, 12, 28, 0))
        XCTAssertEqual(range.end, date(2027, 1, 4, 0))
        XCTAssertTrue(TripDateMode.week.includes(anchor, anchor: anchor, calendar: calendar))
        XCTAssertFalse(TripDateMode.week.includes(range.end, anchor: anchor, calendar: calendar))
    }
    func testMonthIncludesLeapDayButNotNextMonth() {
        let anchor = date(2028, 2, 15)
        XCTAssertTrue(TripDateMode.month.includes(date(2028, 2, 29), anchor: anchor, calendar: calendar))
        XCTAssertFalse(TripDateMode.month.includes(date(2028, 3, 1, 0), anchor: anchor, calendar: calendar))
    }
    func testYearAndStatusIndependentRangeDoesNotIncludeNextYear() {
        let anchor = date(2026, 11, 16)
        XCTAssertTrue(TripDateMode.year.includes(date(2026, 1, 1, 0), anchor: anchor, calendar: calendar))
        XCTAssertTrue(TripDateMode.year.includes(date(2026, 12, 31, 23), anchor: anchor, calendar: calendar))
        XCTAssertFalse(TripDateMode.year.includes(date(2027, 1, 1, 0), anchor: anchor, calendar: calendar))
    }
    func testDSTAndMonthNavigationUseCalendarNotFixedSeconds() {
        let anchor = date(2026, 3, 8)
        XCTAssertEqual(TripDateMode.day.interval(anchor: anchor, calendar: calendar).duration, 23 * 3600)
        let fall = date(2026, 11, 1)
        XCTAssertEqual(TripDateMode.day.interval(anchor: fall, calendar: calendar).duration, 25 * 3600)
        XCTAssertEqual(TripDateMode.month.shifted(date(2028, 1, 31), by: 1, calendar: calendar), date(2028, 2, 29))
    }
}

final class BusinessCardExportRenderingTests: XCTestCase {
    @MainActor func testBothCardStylesRenderLongEmailAtPhoneAndExportWidths() throws {
        for style in [0, 1] {
            for width: CGFloat in [320, 600] {
                let card = BusinessCardPreview(name: "PRIVATE NAME MUST NOT APPEAR", phone: "+1 (213) 555-0148",
                    email: "alexander.transport.service.very.long.address@example.com", nickname: "",
                    portraitData: nil, qrCodeData: nil, style: style)
                let renderer = ImageRenderer(content: card.frame(width: width).padding(20).background(Color.white))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, width + 40, accuracy: 1)
                XCTAssertGreaterThan(image.size.height, 100)
                XCTAssertFalse(try XCTUnwrap(image.pngData()).isEmpty)
                let attachment = XCTAttachment(image: image)
                attachment.name = "business-card-style-\(style)-width-\(Int(width))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}

final class CustomerHistoryNetIncomeTests: XCTestCase {
    func testHistoryNetIncludesTipAdditionsAndDeductions() {
        var trip = CloudOnlineRepository.CustomerTripRecord(id: "t", customerID: "c", customerName: "QA", serviceType: "接机", appointmentDate: "2026-11-17", locationEnd: "QA", price: 100, tip: 20, isPaid: false, isCompleted: false, isCancelled: false, currencyCode: "USD")
        trip.expenses = [
            .init(id: "a", tripID: "t", position: 0, isAddition: true, title: "Extra", amount: -10),
            .init(id: "d", tripID: "t", position: 1, isAddition: false, title: "Parking", amount: -25)
        ]
        XCTAssertEqual(trip.netIncome, 105)
        trip.expenses = [.init(id: "d", tripID: "t", position: 0, isAddition: false, title: "Cost", amount: 150)]
        XCTAssertEqual(trip.netIncome, -30)
    }
}

final class CustomerHistoryExpenseLoadingTests: XCTestCase {
    @MainActor func testHistoryAttachesOnlyItsTripExpensesAndPropagatesExpenseFailure() async throws {
        let owner = "00000000-0000-0000-0000-000000000001"
        let customer = "00000000-0000-0000-0000-000000000002"
        let email = "history-net@example.invalid"
        let oldScope = DataOwnership.activeScope
        DataOwnership.activateCloud(email: email)
        XCTAssertTrue(URLProtocol.registerClass(SyncFixtureProtocol.self))
        var failExpenses = false
        SyncFixtureProtocol.handle = { fixture in
            let path = fixture.request.url!.path
            if path == "/auth/v1/user" { fixture.respond("{\"id\":\"\(owner)\",\"email\":\"\(email)\"}"); return }
            let query = URLComponents(url: fixture.request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
            XCTAssertEqual(query.first { $0.name == "owner_id" }?.value, "eq.\(owner)")
            XCTAssertEqual(query.first { $0.name == "deleted_at" }?.value, "is.null")
            if path.hasSuffix("trip_expenses") {
                if failExpenses { fixture.respond("{\"message\":\"fixture failure\"}", status: 500); return }
                fixture.respond("[{\"id\":\"e\",\"trip_id\":\"t\",\"position\":0,\"is_addition\":false,\"title\":\"Cost\",\"amount\":25},{\"id\":\"other\",\"trip_id\":\"other\",\"position\":0,\"is_addition\":false,\"title\":\"Other\",\"amount\":999}]")
            } else {
                XCTAssertEqual(query.first { $0.name == "customer_id" }?.value, "eq.\(customer)")
                fixture.respond("[{\"id\":\"t\",\"customer_id\":\"\(customer)\",\"customer_name\":\"QA\",\"service_type\":\"接机\",\"appointment_date\":\"2026-11-17\",\"location_end\":\"QA\",\"price\":100,\"tip\":20,\"is_paid\":false,\"is_completed\":false,\"is_cancelled\":false,\"currency_code\":\"USD\"}]")
            }
        }
        defer { SyncFixtureProtocol.handle = nil; URLProtocol.unregisterClass(SyncFixtureProtocol.self); DataOwnership.activateLocal(scope: oldScope) }
        let account = CloudOnlineRepository.Account(id: owner, email: email)
        let trips = try await CloudOnlineRepository.fetchCustomerTrips(customerID: customer, account: account, accessToken: "fixture-only")
        XCTAssertEqual(trips.first?.netIncome, 95)
        XCTAssertEqual(trips.first?.expenses.count, 1)
        failExpenses = true
        do { _ = try await CloudOnlineRepository.fetchCustomerTrips(customerID: customer, account: account, accessToken: "fixture-only"); XCTFail("Cannot display fare as net when expenses fail") }
        catch { }
    }
}

final class RememberedLoginTests: XCTestCase {
    @MainActor func testMigratesPriorSingleAccountWithoutEnablingBiometrics() throws {
        let suite = "TrvelMA.RememberedLoginTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "auth.rememberEmail")
        defaults.set(" Local@Example.invalid ", forKey: "auth.rememberedEmail")
        defaults.set(false, forKey: "auth.accountMode.cloud")
        let accounts = RememberedLogins.load(defaults: defaults)
        XCTAssertEqual(accounts, [.init(email: "local@example.invalid", isCloud: false)])
        XCTAssertNil(defaults.string(forKey: "auth.rememberedEmail"))
        XCTAssertEqual(RememberedLogins.load(defaults: defaults), accounts)
    }

    @MainActor func testHistoryKeepsLoginModesSeparateAndMovesRepeatToFront() throws {
        let suite = "TrvelMA.RememberedLoginTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = RememberedLogin(email: "same@example.invalid", isCloud: true, usesBiometrics: true)
        let local = RememberedLogin(email: "same@example.invalid", isCloud: false)
        RememberedLogins.record(cloud, defaults: defaults)
        RememberedLogins.record(local, defaults: defaults)
        XCTAssertEqual(RememberedLogins.load(defaults: defaults), [local, cloud])
        RememberedLogins.record(.init(email: "SAME@example.invalid", isCloud: true), defaults: defaults)
        XCTAssertEqual(RememberedLogins.load(defaults: defaults), [.init(email: cloud.email, isCloud: true), local])
    }
}
