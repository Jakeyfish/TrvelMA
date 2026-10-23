import Foundation
import SwiftData

/// Copies the former shared store into account-mode stores without deleting the
/// source database. Copies are keyed by the models' stable identifiers, so a
/// partially completed run can safely be retried.
@MainActor
enum LegacyStoreMigrator {
    private static let completionKey = "data.storeMigration.sharedToAccount.v1"

    struct Summary {
        var localCustomers = 0
        var cloudCustomers = 0
        var localAgencies = 0
        var cloudAgencies = 0
        var localTrips = 0
        var cloudTrips = 0
        var localDeletionRecords = 0
        var cloudDeletionRecords = 0
        var localAccounts = 0
        var loginRecords = 0
    }

    enum MigrationError: LocalizedError {
        case verificationFailed(String)
        case storesUnavailable

        var errorDescription: String? {
            switch self {
            case .verificationFailed(let details):
                String(format: String(localized: "旧资料迁移未通过完整性检查（%@）。原数据库已保留，请勿删除或重置应用数据。"), details)
            case .storesUnavailable:
                String(localized: "本机或云端资料库尚未准备好，请重试。")
            }
        }
    }

    static func migrateLegacyDefaultStoreIfNeeded(toLocal local: ModelContainer, toCloud cloud: ModelContainer) throws -> Summary? {
        guard !UserDefaults.standard.bool(forKey: completionKey) else { return nil }
        guard let legacy = try AppDataSchema.openLegacyDefaultContainerIfPresent() else {
            UserDefaults.standard.set(true, forKey: completionKey)
            return nil
        }
        let result = try migrate(from: legacy, toLocal: local, toCloud: cloud)
        UserDefaults.standard.set(true, forKey: completionKey)
        return result
    }

    static func migrate(from source: ModelContainer, toLocal local: ModelContainer, toCloud cloud: ModelContainer) throws -> Summary {
        let sourceContext = ModelContext(source)
        let localContext = ModelContext(local)
        let cloudContext = ModelContext(cloud)
        let sourceCustomers = try sourceContext.fetch(FetchDescriptor<Custumer>())
        let sourceAgencies = try sourceContext.fetch(FetchDescriptor<TravelAgency>())
        let sourceTrips = try sourceContext.fetch(FetchDescriptor<TripBookingRecord>())
        let sourceDeletions = try sourceContext.fetch(FetchDescriptor<CloudSyncDeletion>())
        let sourceConflicts = try sourceContext.fetch(FetchDescriptor<CloudSyncConflict>())
        let sourceAccounts = try sourceContext.fetch(FetchDescriptor<LocalAccount>())
        let sourceLogins = try sourceContext.fetch(FetchDescriptor<LoginInfo>())

        var summary = Summary()
        copyCustomers(sourceCustomers.filter { isLocal($0.ownerScope) }, into: localContext, count: &summary.localCustomers)
        copyCustomers(sourceCustomers.filter { !isLocal($0.ownerScope) }, into: cloudContext, count: &summary.cloudCustomers)
        copyAgencies(sourceAgencies.filter { isLocal($0.ownerScope) }, into: localContext, count: &summary.localAgencies)
        copyAgencies(sourceAgencies.filter { !isLocal($0.ownerScope) }, into: cloudContext, count: &summary.cloudAgencies)
        copyTrips(sourceTrips.filter { isLocal($0.ownerScope) }, into: localContext, count: &summary.localTrips)
        copyTrips(sourceTrips.filter { !isLocal($0.ownerScope) }, into: cloudContext, count: &summary.cloudTrips)
        copyDeletions(sourceDeletions.filter { isLocal($0.ownerScope) }, into: localContext, count: &summary.localDeletionRecords)
        copyDeletions(sourceDeletions.filter { !isLocal($0.ownerScope) }, into: cloudContext, count: &summary.cloudDeletionRecords)
        copyConflicts(sourceConflicts.filter { isLocal($0.ownerScope) }, into: localContext)
        copyConflicts(sourceConflicts.filter { !isLocal($0.ownerScope) }, into: cloudContext)
        copyLocalAccounts(sourceAccounts, into: localContext, count: &summary.localAccounts)
        copyLogins(sourceLogins, into: localContext, count: &summary.loginRecords)

        try localContext.save()
        try cloudContext.save()
        try verify(sourceCustomers, sourceAgencies, sourceTrips, sourceDeletions, sourceAccounts, sourceLogins, localContext: localContext, cloudContext: cloudContext)
        return summary
    }

    /// Copies the selected local account into the cloud cache after explicit
    /// user consent. The source account remains untouched in the local store.
    static func importLocalRecordsToCloud(from local: ModelContainer, into cloud: ModelContainer,
                                          fromLocalEmail: String, toCloudEmail: String) throws {
        let sourceScope = fromLocalEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? DataOwnership.legacyLocalScope
            : DataOwnership.localScope(email: fromLocalEmail)
        let targetScope = DataOwnership.cloudScope(for: toCloudEmail)
        let sourceContext = ModelContext(local)
        let cloudContext = ModelContext(cloud)

        let customers = try sourceContext.fetch(FetchDescriptor<Custumer>())
            .filter { $0.ownerScope == sourceScope || $0.ownerScope == DataOwnership.legacyLocalScope }
        let agencies = try sourceContext.fetch(FetchDescriptor<TravelAgency>())
            .filter { $0.ownerScope == sourceScope || $0.ownerScope == DataOwnership.legacyLocalScope }
        let trips = try sourceContext.fetch(FetchDescriptor<TripBookingRecord>())
            .filter { $0.ownerScope == sourceScope || $0.ownerScope == DataOwnership.legacyLocalScope }
        let deletions = try sourceContext.fetch(FetchDescriptor<CloudSyncDeletion>())
            .filter { $0.ownerScope == sourceScope || $0.ownerScope == DataOwnership.legacyLocalScope }
        let conflicts = try sourceContext.fetch(FetchDescriptor<CloudSyncConflict>())
            .filter { $0.ownerScope == sourceScope || $0.ownerScope == DataOwnership.legacyLocalScope }

        var ignoredCount = 0
        copyCustomers(customers, into: cloudContext, count: &ignoredCount, ownerScope: targetScope)
        copyAgencies(agencies, into: cloudContext, count: &ignoredCount, ownerScope: targetScope)
        copyTrips(trips, into: cloudContext, count: &ignoredCount, ownerScope: targetScope)
        copyDeletions(deletions, into: cloudContext, count: &ignoredCount, ownerScope: targetScope)
        copyConflicts(conflicts, into: cloudContext, ownerScope: targetScope)
        try cloudContext.save()

        let cloudCustomers = try cloudContext.fetch(FetchDescriptor<Custumer>(predicate: #Predicate { $0.ownerScope == targetScope }))
        let cloudCustomerIDs = Set(cloudCustomers.map(\.uuid))
        let cloudAgencyIDs = Set(try cloudContext.fetch(FetchDescriptor<TravelAgency>(predicate: #Predicate { $0.ownerScope == targetScope })).map(\.uuid))
        let cloudTripIDs = Set(try cloudContext.fetch(FetchDescriptor<TripBookingRecord>(predicate: #Predicate { $0.ownerScope == targetScope })).map(\.id))
        let cloudDeletionKeys = Set(try cloudContext.fetch(FetchDescriptor<CloudSyncDeletion>(predicate: #Predicate { $0.ownerScope == targetScope })).map(\.key))
        guard Set(customers.map(\.uuid)).isSubset(of: cloudCustomerIDs),
              Set(agencies.map(\.uuid)).isSubset(of: cloudAgencyIDs),
              Set(trips.map(\.id)).isSubset(of: cloudTripIDs),
              Set(deletions.map(\.key)).isSubset(of: cloudDeletionKeys) else {
            throw MigrationError.verificationFailed("云端客户、旅行社、行程或删除记录缺失")
        }
    }

    private static func isLocal(_ scope: String) -> Bool {
        DataOwnership.isLocalScope(scope)
    }

    private static func copyCustomers(_ source: [Custumer], into context: ModelContext, count: inout Int,
                                     ownerScope: String? = nil) {
        let existing = Set((try? context.fetch(FetchDescriptor<Custumer>()).map(\.uuid)) ?? [])
        for item in source where !existing.contains(item.uuid) {
            let copy = Custumer(
                uuid: item.uuid,
                version: item.version,
                syncState: item.syncState,
                name: item.name,
                email: item.email,
                avatarUrl: item.avatarUrl,
                csource: item.csource,
                type: item.type,
                customerCategory: item.customerCategory,
                travelAgencyCode: item.travelAgencyCode,
                travelAgencyName: item.travelAgencyName,
                languagePreference: item.languagePreference,
                remark: item.remark,
                createdAt: item.createdAt,
                updateAt: item.updateAt,
                syncBaseUpdatedAt: item.syncBaseUpdatedAt
            )
            copy.ownerScope = ownerScope ?? item.ownerScope
            copy.addresses = item.addresses.map { Address(addlable: $0.addlable, addresses: $0.addresses, isDefault: $0.isDefault, customer: copy) }
            copy.connecttype = item.connecttype.map { Connect(connectlable: $0.connectlable, connecttype: $0.connecttype, isDefault: $0.isDefault, customer: copy) }
            context.insert(copy)
            count += 1
        }
    }

    private static func copyAgencies(_ source: [TravelAgency], into context: ModelContext, count: inout Int,
                                    ownerScope: String? = nil) {
        let existing = Set((try? context.fetch(FetchDescriptor<TravelAgency>()).map(\.uuid)) ?? [])
        for item in source where !existing.contains(item.uuid) {
            let copy = TravelAgency(uuid: item.uuid, agencyCode: item.agencyCode, name: item.name, contactPerson: item.contactPerson, phone: item.phone, officeAddress: item.officeAddress, createdAt: item.createdAt, updateAt: item.updateAt, syncBaseUpdatedAt: item.syncBaseUpdatedAt)
            copy.ownerScope = ownerScope ?? item.ownerScope
            context.insert(copy)
            count += 1
        }
    }

    private static func copyTrips(_ source: [TripBookingRecord], into context: ModelContext, count: inout Int,
                                 ownerScope: String? = nil) {
        let existing = Set((try? context.fetch(FetchDescriptor<TripBookingRecord>()).map(\.id)) ?? [])
        for item in source where !existing.contains(item.id) {
            let copy = TripBookingRecord(copying: item)
            if let ownerScope { copy.ownerScope = ownerScope }
            context.insert(copy)
            count += 1
        }
    }

    private static func copyDeletions(_ source: [CloudSyncDeletion], into context: ModelContext, count: inout Int,
                                     ownerScope: String? = nil) {
        let existing = Set((try? context.fetch(FetchDescriptor<CloudSyncDeletion>()).map(\.key)) ?? [])
        for item in source where !existing.contains(item.key) {
            let copy = CloudSyncDeletion(tableName: item.tableName, recordID: item.recordID, deletedAt: item.deletedAt, baseUpdatedAt: item.baseUpdatedAt)
            copy.key = item.key
            copy.ownerScope = ownerScope ?? item.ownerScope
            context.insert(copy)
            count += 1
        }
    }

    private static func copyConflicts(_ source: [CloudSyncConflict], into context: ModelContext, ownerScope: String? = nil) {
        let existing = Set((try? context.fetch(FetchDescriptor<CloudSyncConflict>()).map(\.key)) ?? [])
        for item in source {
            let targetScope = ownerScope ?? item.ownerScope
            let targetKey = "\(targetScope)|\(item.tableName)|\(item.recordID.lowercased())"
            guard !existing.contains(targetKey) else { continue }
            context.insert(CloudSyncConflict(tableName: item.tableName, recordID: item.recordID,
                                             ownerScope: targetScope, localUpdatedAt: item.localUpdatedAt,
                                             remoteUpdatedAt: item.remoteUpdatedAt,
                                             remotePayloadJSON: item.remotePayloadJSON,
                                             isLocalDeletion: item.isLocalDeletion,
                                             isRemoteDeletion: item.isRemoteDeletion))
        }
    }

    private static func copyLocalAccounts(_ source: [LocalAccount], into context: ModelContext, count: inout Int) {
        let existing = Set((try? context.fetch(FetchDescriptor<LocalAccount>()).map(\.email)) ?? [])
        for item in source where !existing.contains(item.email) {
            let copy = LocalAccount(email: item.email, salutation: item.salutation, phone: item.phone, createdAt: item.createdAt)
            copy.updatedAt = item.updatedAt
            copy.syncID = item.syncID
            copy.schemaVersion = item.schemaVersion
            copy.syncState = item.syncState
            context.insert(copy)
            count += 1
        }
    }

    private static func copyLogins(_ source: [LoginInfo], into context: ModelContext, count: inout Int) {
        let existing = Set((try? context.fetch(FetchDescriptor<LoginInfo>()).map(\.serverUserId)) ?? [])
        for item in source where !existing.contains(item.serverUserId) {
            let copy = LoginInfo(serverUserId: item.serverUserId, username: item.username, loginToken: item.loginToken, tokenExpiredAt: item.tokenExpiredAt, lastLoginAt: item.lastLoginAt, isRemembered: item.isRemembered)
            if let profile = item.profile {
                copy.profile = ProfileInfo(nickname: profile.nickname, avatarUrl: profile.avatarUrl, gender: profile.gender, birthday: profile.birthday, bio: profile.bio, region: profile.region, phone: profile.phone, email: profile.email, weChatQrcode: profile.weChatQrcode, lineQrcode: profile.lineQrcode, whatsAppQrcode: profile.whatsAppQrcode, loginInfo: copy)
            }
            context.insert(copy)
            count += 1
        }
    }

    private static func verify(_ customers: [Custumer], _ agencies: [TravelAgency], _ trips: [TripBookingRecord], _ deletions: [CloudSyncDeletion], _ accounts: [LocalAccount], _ logins: [LoginInfo], localContext: ModelContext, cloudContext: ModelContext) throws {
        let localCustomerIDs = Set(try localContext.fetch(FetchDescriptor<Custumer>()).map(\.uuid))
        let cloudCustomerIDs = Set(try cloudContext.fetch(FetchDescriptor<Custumer>()).map(\.uuid))
        let localAgencyIDs = Set(try localContext.fetch(FetchDescriptor<TravelAgency>()).map(\.uuid))
        let cloudAgencyIDs = Set(try cloudContext.fetch(FetchDescriptor<TravelAgency>()).map(\.uuid))
        let localTripIDs = Set(try localContext.fetch(FetchDescriptor<TripBookingRecord>()).map(\.id))
        let cloudTripIDs = Set(try cloudContext.fetch(FetchDescriptor<TripBookingRecord>()).map(\.id))
        let localDeletionKeys = Set(try localContext.fetch(FetchDescriptor<CloudSyncDeletion>()).map(\.key))
        let cloudDeletionKeys = Set(try cloudContext.fetch(FetchDescriptor<CloudSyncDeletion>()).map(\.key))
        let localAccountEmails = Set(try localContext.fetch(FetchDescriptor<LocalAccount>()).map(\.email))
        let localLoginIDs = Set(try localContext.fetch(FetchDescriptor<LoginInfo>()).map(\.serverUserId))

        let expectedLocalCustomers = Set(customers.filter { isLocal($0.ownerScope) }.map(\.uuid))
        let expectedCloudCustomers = Set(customers.filter { !isLocal($0.ownerScope) }.map(\.uuid))
        let expectedLocalAgencies = Set(agencies.filter { isLocal($0.ownerScope) }.map(\.uuid))
        let expectedCloudAgencies = Set(agencies.filter { !isLocal($0.ownerScope) }.map(\.uuid))
        let expectedLocalTrips = Set(trips.filter { isLocal($0.ownerScope) }.map(\.id))
        let expectedCloudTrips = Set(trips.filter { !isLocal($0.ownerScope) }.map(\.id))
        let expectedLocalDeletions = Set(deletions.filter { isLocal($0.ownerScope) }.map(\.key))
        let expectedCloudDeletions = Set(deletions.filter { !isLocal($0.ownerScope) }.map(\.key))

        let sourceLocalAccounts = Set(accounts.map(\.email))
        let sourceLoginIDs = Set(logins.map(\.serverUserId))
        var missing: [String] = []
        appendMissing(expectedLocalCustomers, from: localCustomerIDs, label: "本机客户", to: &missing)
        appendMissing(expectedCloudCustomers, from: cloudCustomerIDs, label: "云端客户", to: &missing)
        appendMissing(expectedLocalAgencies, from: localAgencyIDs, label: "本机旅行社", to: &missing)
        appendMissing(expectedCloudAgencies, from: cloudAgencyIDs, label: "云端旅行社", to: &missing)
        appendMissing(expectedLocalTrips, from: localTripIDs, label: "本机行程", to: &missing)
        appendMissing(expectedCloudTrips, from: cloudTripIDs, label: "云端行程", to: &missing)
        appendMissing(expectedLocalDeletions, from: localDeletionKeys, label: "本机删除记录", to: &missing)
        appendMissing(expectedCloudDeletions, from: cloudDeletionKeys, label: "云端删除记录", to: &missing)
        appendMissing(sourceLocalAccounts, from: localAccountEmails, label: "本机账号", to: &missing)
        appendMissing(sourceLoginIDs, from: localLoginIDs, label: "登录资料", to: &missing)
        if !missing.isEmpty {
            throw MigrationError.verificationFailed(missing.joined(separator: "、"))
        }
    }

    private static func appendMissing<ID: Hashable>(_ expected: Set<ID>, from actual: Set<ID>, label: String, to missing: inout [String]) {
        let count = expected.subtracting(actual).count
        if count > 0 { missing.append("\(label)缺失 \(count) 条") }
    }

}
