import Foundation
import SwiftData

enum CloudLocalDataPreference: String, CaseIterable, Identifiable {
    case syncLocalData
    case cloudDataOnly

    var id: String { rawValue }

    static func key(for email: String) -> String {
        "auth.cloud.localDataPreference.v1.\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    static func load(for email: String) -> Self? {
        guard let rawValue = UserDefaults.standard.string(forKey: key(for: email)) else { return nil }
        return Self(rawValue: rawValue)
    }

    func save(for email: String) {
        UserDefaults.standard.set(rawValue, forKey: Self.key(for: email))
    }
}

/// Separates the device-only workspace from each authenticated cloud account.
/// Existing records without a scope are migrated to `local` by SwiftData's
/// lightweight schema migration, so they remain on-device until the user opts in.
enum DataOwnership {
    static let legacyLocalScope = "local"
    private static let activeScopeKey = "data.activeOwnerScope.v1"

    static var activeScope: String {
        UserDefaults.standard.string(forKey: activeScopeKey) ?? legacyLocalScope
    }

    static func localScope(accountID: String) -> String { "local:\(accountID.lowercased())" }

    static func localScope(email: String) -> String {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let idKey = "data.localOwnerID.v1.\(normalizedEmail)"
        let ownerID = UserDefaults.standard.string(forKey: idKey) ?? UUID().uuidString.lowercased()
        UserDefaults.standard.set(ownerID, forKey: idKey)
        return localScope(accountID: ownerID)
    }

    static func cloudScope(for email: String) -> String {
        "cloud:\(email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    static func activateLocal(scope: String) {
        UserDefaults.standard.set(scope, forKey: activeScopeKey)
    }

    static func activateLocal(email: String = "") {
        activateLocal(scope: localScope(email: email))
    }

    static func activateCloud(email: String) {
        UserDefaults.standard.set(cloudScope(for: email), forKey: activeScopeKey)
    }

    @MainActor
    static func adoptLegacyLocalRecords(context: ModelContext, scope: String) throws {
        let legacyScope = legacyLocalScope
        for item in try context.fetch(FetchDescriptor<Custumer>(predicate: #Predicate { $0.ownerScope == legacyScope })) {
            item.ownerScope = scope
            for child in item.connecttype { child.ownerScope = scope }
            for child in item.addresses { child.ownerScope = scope }
        }
        for item in try context.fetch(FetchDescriptor<TravelAgency>(predicate: #Predicate { $0.ownerScope == legacyScope })) {
            item.ownerScope = scope
        }
        for item in try context.fetch(FetchDescriptor<TripBookingRecord>(predicate: #Predicate { $0.ownerScope == legacyScope })) {
            item.ownerScope = scope
        }
        for item in try context.fetch(FetchDescriptor<CloudSyncDeletion>(predicate: #Predicate { $0.ownerScope == legacyScope })) {
            item.ownerScope = scope
        }
        try context.save()
    }

    static func isLocalScope(_ scope: String) -> Bool {
        scope == legacyLocalScope || scope.hasPrefix("local:")
    }

    static func hasUnimportedLocalAssets(from localEmail: String, to cloudEmail: String) -> Bool {
        AccountAssetStore.hasUnimportedLocalAssets(from: localEmail, to: cloudEmail)
    }
}
