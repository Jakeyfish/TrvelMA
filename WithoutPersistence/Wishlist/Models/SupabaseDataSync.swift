import Foundation
import SwiftData
import CryptoKit
import UIKit

extension Notification.Name {
    static let accountAssetsDidChange = Notification.Name("accountAssetsDidChange")
    static let accountAssetsDidSync = Notification.Name("accountAssetsDidSync")
}

@Model
final class CloudSyncDeletion {
    @Attribute(.unique) var key: String
    var ownerScope: String = "local"
    var tableName: String
    var recordID: String
    var deletedAt: Date
    var baseUpdatedAt: Date? = nil

    init(tableName: String, recordID: String, deletedAt: Date = .now, baseUpdatedAt: Date? = nil) {
        self.tableName = tableName
        self.recordID = recordID
        self.deletedAt = deletedAt
        self.baseUpdatedAt = baseUpdatedAt
        self.key = "\(tableName):\(recordID.lowercased())"
        self.ownerScope = DataOwnership.activeScope
    }
}

/// Holds the remote copy of a record when both devices edited it after the
/// same acknowledged version. Keeping this row blocks automatic upload until
/// the user chooses which copy to keep.
@Model
final class CloudSyncConflict {
    @Attribute(.unique) var key: String
    var ownerScope: String = "local"
    var tableName: String
    var recordID: String
    var localUpdatedAt: Date
    var remoteUpdatedAt: Date
    var remotePayloadJSON: String
    var isLocalDeletion: Bool = false
    var isRemoteDeletion: Bool = false
    var createdAt: Date

    init(tableName: String, recordID: String, ownerScope: String, localUpdatedAt: Date,
         remoteUpdatedAt: Date, remotePayloadJSON: String, isLocalDeletion: Bool = false,
         isRemoteDeletion: Bool = false) {
        self.tableName = tableName
        self.recordID = recordID
        self.ownerScope = ownerScope
        self.localUpdatedAt = localUpdatedAt
        self.remoteUpdatedAt = remoteUpdatedAt
        self.remotePayloadJSON = remotePayloadJSON
        self.isLocalDeletion = isLocalDeletion
        self.isRemoteDeletion = isRemoteDeletion
        self.createdAt = Date()
        self.key = "\(ownerScope)|\(tableName)|\(recordID.lowercased())"
    }
}

/// Keeps a record alive while its detail screen is on screen. A remote delete
/// during that interval must become a resolvable conflict instead of deleting
/// the SwiftData object out from under the active SwiftUI navigation stack.
@MainActor
enum SyncEditRegistry {
    private static var activeRecords: [String: Int] = [:]

    static func begin(table: String, id: String, scope: String) {
        let key = "\(scope)|\(table)|\(id.lowercased())"
        activeRecords[key, default: 0] += 1
    }

    static func end(table: String, id: String, scope: String) {
        let key = "\(scope)|\(table)|\(id.lowercased())"
        let remaining = (activeRecords[key] ?? 1) - 1
        if remaining <= 0 { activeRecords.removeValue(forKey: key) }
        else { activeRecords[key] = remaining }
    }

    static func isEditing(table: String, id: String, scope: String) -> Bool {
        let key = "\(scope)|\(table)|\(id.lowercased())"
        return activeRecords[key, default: 0] > 0
    }
}

/// Reconciles local SwiftData rows with the authenticated Supabase account.
/// RLS uses the JWT, so every row is explicitly tagged with the JWT's owner id.
enum SupabaseDataSync {
    struct Summary {
        var customers = 0
        var agencies = 0
        var trips = 0
        var downloaded = 0
        var uploaded = 0
        var deleted = 0
    }

    @MainActor
    static func recordDeletion(table: String, id: String, context: ModelContext) {
        let key = "\(table):\(id.lowercased())"
        let scope = DataOwnership.activeScope
        let descriptor = FetchDescriptor<CloudSyncDeletion>(predicate: #Predicate { $0.key == key && $0.ownerScope == scope })
        if let existing = try? context.fetch(descriptor).first {
            existing.deletedAt = .now
        } else {
            let baseUpdatedAt: Date?
            switch table {
            case "customers":
                let descriptor = FetchDescriptor<Custumer>(predicate: #Predicate { $0.uuid == id && $0.ownerScope == scope })
                baseUpdatedAt = (try? context.fetch(descriptor).first)?.syncBaseUpdatedAt
            case "travel_agencies":
                let descriptor = FetchDescriptor<TravelAgency>(predicate: #Predicate { $0.uuid == id && $0.ownerScope == scope })
                baseUpdatedAt = (try? context.fetch(descriptor).first)?.syncBaseUpdatedAt
            case "trips":
                guard let tripID = UUID(uuidString: id) else { baseUpdatedAt = nil; context.insert(CloudSyncDeletion(tableName: table, recordID: id)); return }
                let descriptor = FetchDescriptor<TripBookingRecord>(predicate: #Predicate { $0.id == tripID && $0.ownerScope == scope })
                baseUpdatedAt = (try? context.fetch(descriptor).first)?.syncBaseUpdatedAt
            default:
                baseUpdatedAt = nil
            }
            context.insert(CloudSyncDeletion(tableName: table, recordID: id, baseUpdatedAt: baseUpdatedAt))
        }
    }

    enum SyncError: LocalizedError {
        case noSession
        case accountChanged
        case response(String)
        var errorDescription: String? {
            switch self {
            case .noSession:
                Self.localized("云端登录状态已失效，请重新登录后同步。")
            case .accountChanged:
                Self.localized("同步期间账号已切换，请重新同步当前账号。")
            case .response(let message):
                Self.localizedKnownMessage(message)
            }
        }

        private static var locale: Locale {
            Locale(identifier: UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans")
        }

        private static func localized(_ key: String) -> String {
            switch key {
            case "云端登录状态已失效，请重新登录后同步。":
                return String(localized: "云端登录状态已失效，请重新登录后同步。", locale: locale)
            case "同步期间账号已切换，请重新同步当前账号。":
                return String(localized: "同步期间账号已切换，请重新同步当前账号。", locale: locale)
            default:
                return key
            }
        }

        private static func localizedKnownMessage(_ message: String) -> String {
            if message.localizedLowercase.contains("all object keys must match") {
                return String(localized: "批量上传的数据字段格式不一致，请更新应用后重新同步。", locale: locale)
            }
            if message == "无法验证云端账号，请重新登录后重试。" {
                return String(localized: "无法验证云端账号，请重新登录后重试。", locale: locale)
            } else if message.hasPrefix("云端数据表未就绪或权限配置不正确（"), message.hasSuffix("）。") {
                let table = String(message.dropFirst("云端数据表未就绪或权限配置不正确（".count).dropLast(2))
                let format = String(localized: "云端数据表未就绪或权限配置不正确（%@）。", locale: locale)
                return String(format: format, locale: locale, arguments: [table as CVarArg])
            }
            return message
        }
    }

    @MainActor
    static func uploadLocalData(context: ModelContext, accessToken: String, accountEmail: String) async throws -> Summary {
        let normalizedEmail = accountEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else { throw SyncError.noSession }
        // Freeze the owner scope before any network await. The active account may
        // change while a request is in flight, but this sync must stay isolated.
        let scope = DataOwnership.cloudScope(for: normalizedEmail)
        let ownerID = try await currentUserID(accessToken: accessToken)
        guard DataOwnership.activeScope == scope else { throw SyncError.accountChanged }
        var summary = Summary()
        let tombstones = try context.fetch(FetchDescriptor<CloudSyncDeletion>(predicate: #Predicate { $0.ownerScope == scope }))
        var cloudDeletionRows: [String: [[String: Any]]] = [:]
        for table in Set(tombstones.map(\.tableName)) {
            cloudDeletionRows[table] = try await fetchRows(table, token: accessToken)
        }
        for tombstone in tombstones {
            if conflictExists(table: tombstone.tableName, id: tombstone.recordID, scope: scope, context: context) {
                continue
            }
            let remoteRow = cloudDeletionRows[tombstone.tableName]?.first {
                string($0, "id")?.lowercased() == tombstone.recordID.lowercased() && !isDeleted($0)
            }
            if let remoteRow, let remoteDate = date(remoteRow, "updated_at") {
                let remoteWasEditedAfterDeleteBaseline = tombstone.baseUpdatedAt.map { remoteDate > $0 } ?? true
                if remoteWasEditedAfterDeleteBaseline {
                    try storeConflict(table: tombstone.tableName, id: tombstone.recordID, scope: scope,
                                      localUpdatedAt: tombstone.deletedAt, remoteUpdatedAt: remoteDate,
                                      row: remoteRow, context: context, isLocalDeletion: true)
                    continue
                }
            }
            try await patchDeleted(tombstone, token: accessToken)
            context.delete(tombstone)
            summary.deleted += 1
        }
        if !tombstones.isEmpty { try context.save() }
        summary.downloaded = try await pullAndMerge(context: context, token: accessToken, scope: scope)
        try deduplicateCustomerChildren(context: context, scope: scope)
        try context.save()
        let pendingConflicts = try context.fetch(FetchDescriptor<CloudSyncConflict>(predicate: #Predicate { $0.ownerScope == scope }))
        let blockedAgencies = Set(pendingConflicts.filter { $0.tableName == "travel_agencies" }.map { $0.recordID.lowercased() })
        let blockedCustomers = Set(pendingConflicts.filter { $0.tableName == "customers" }.map { $0.recordID.lowercased() })
        let blockedTrips = Set(pendingConflicts.filter { $0.tableName == "trips" }.map { $0.recordID.lowercased() })
        let agencies = try context.fetch(FetchDescriptor<TravelAgency>(predicate: #Predicate { $0.ownerScope == scope })).filter { !blockedAgencies.contains($0.uuid.lowercased()) }
        let customers = try context.fetch(FetchDescriptor<Custumer>(predicate: #Predicate { $0.ownerScope == scope })).filter { !blockedCustomers.contains($0.uuid.lowercased()) }
        let trips = try context.fetch(FetchDescriptor<TripBookingRecord>(predicate: #Predicate { $0.ownerScope == scope })).filter { !blockedTrips.contains($0.id.uuidString.lowercased()) }

        try await upsert("travel_agencies", rows: agencies.map { agency in
            ["id": agency.uuid, "owner_id": ownerID, "agency_code": agency.agencyCode,
             "name": agency.name, "contact_person": agency.contactPerson, "phone": agency.phone,
             "office_address": agency.officeAddress, "created_at": iso(agency.createdAt), "updated_at": iso(agency.updateAt), "deleted_at": NSNull()]
        }, token: accessToken)
        summary.agencies = agencies.count

        try await upsert("customers", rows: customers.map { customer in
            ["id": customer.uuid, "owner_id": ownerID, "name": customer.name, "email": customer.email,
             "avatar_url": customer.avatarUrl, "source": customer.csource, "type": customer.type,
             "category": customer.customerCategory, "travel_agency_code": customer.travelAgencyCode,
             "travel_agency_name": customer.travelAgencyName, "language_preference": customer.languagePreference,
             "remark": customer.remark, "created_at": iso(customer.createdAt), "updated_at": iso(customer.updateAt), "deleted_at": NSNull()]
        }, token: accessToken)
        summary.customers = customers.count

        var contacts: [[String: Any]] = []
        var addresses: [[String: Any]] = []
        for customer in customers {
            for (index, contact) in customer.connecttype.enumerated() {
                contacts.append(["id": stableUUID("contact|\(customer.uuid)|\(index)"),
                                 "owner_id": ownerID, "customer_id": customer.uuid, "label": contact.connectlable,
                                 "contact_type": contact.connectlable, "value": contact.connecttype,
                                 "is_default": contact.isDefault, "updated_at": iso(customer.updateAt), "deleted_at": NSNull()])
            }
            for (index, address) in customer.addresses.enumerated() {
                addresses.append(["id": stableUUID("address|\(customer.uuid)|\(index)"),
                                  "owner_id": ownerID, "customer_id": customer.uuid, "label": address.addlable,
                                  "address": address.addresses, "is_default": address.isDefault, "updated_at": iso(customer.updateAt), "deleted_at": NSNull()])
            }
        }
        try await markChildrenDeleted(table: "customer_contacts", parentColumn: "customer_id", parentIDs: customers.map(\.uuid), token: accessToken)
        try await markChildrenDeleted(table: "customer_addresses", parentColumn: "customer_id", parentIDs: customers.map(\.uuid), token: accessToken)
        try await upsert("customer_contacts", rows: contacts, token: accessToken)
        try await upsert("customer_addresses", rows: addresses, token: accessToken)

        try await upsert("trips", rows: trips.map { trip in
            let row: [String: Any] = [
                "id": trip.id.uuidString.lowercased(), "owner_id": ownerID, "service_type": trip.serviceType,
                "order_source": trip.orderSource, "travel_agency_code": trip.travelAgencyCode,
                "travel_agency_name": trip.travelAgencyName, "customer_name": trip.customerName,
                "customer_contact": trip.customerContact, "customer_count": trip.customerCount,
                "customer_stuff": trip.customerStuff, "appointment_date": iso(trip.appointmentDate),
                "appointment_time": iso(trip.appointmentTime), "location_start": trip.locationStart,
                "location_end": trip.locationEnd, "flight_info": trip.flightInfo, "flight_date": iso(trip.flightDate),
                "memo": trip.memo, "price": trip.price, "tip": trip.tip, "is_paid": trip.isPaid,
                "is_completed": trip.isCompleted, "is_cancelled": trip.isCancelled,
                "reminder_enabled": trip.reminderEnabled, "has_second_reminder": trip.hasSecondReminder,
                "currency_code": BaseCurrencyCatalog.option(for: UserDefaults.standard.string(forKey: BaseCurrencyCatalog.countryCodeKey) ?? BaseCurrencyCatalog.defaultCountryCode).currencyCode,
                "created_at": iso(trip.createdAt), "updated_at": iso(trip.updatedAt ?? trip.createdAt), "deleted_at": NSNull(),
                "customer_id": nullable(trip.customerUUID),
                "flight_departure_time": nullable(trip.flightDepartureTime),
                "flight_estimated_arrival_time": nullable(trip.flightEstimatedArrivalTime),
                "flight_arrival_terminal": nullable(trip.flightArrivalTerminal),
                "flight_baggage_carousel": nullable(trip.flightBaggageCarousel),
                "reminder_at": nullable(trip.reminderDateTime.map(iso)),
                "second_reminder_at": nullable(trip.secondReminderDateTime.map(iso))
            ]
            return row
        }, token: accessToken)

        var stops: [[String: Any]] = []
        var expenses: [[String: Any]] = []
        for trip in trips {
            let tripID = trip.id.uuidString.lowercased()
            let tripUpdatedAt = trip.updatedAt ?? trip.createdAt
            for (index, stop) in trip.locationStops.enumerated() {
                stops.append(["id": stableUUID("stop|\(tripID)|\(index)"), "owner_id": ownerID,
                              "trip_id": tripID, "position": index, "address": stop, "updated_at": iso(tripUpdatedAt), "deleted_at": NSNull()])
            }
            for (index, expense) in trip.expenseAdjustments.enumerated() {
                expenses.append(["id": expense.id.uuidString.lowercased(), "owner_id": ownerID, "trip_id": tripID,
                                 "position": index, "is_addition": expense.isAddition,
                                 "title": expense.title, "amount": expense.amount, "updated_at": iso(tripUpdatedAt), "deleted_at": NSNull()])
            }
        }
        try await markChildrenDeleted(table: "trip_stops", parentColumn: "trip_id", parentIDs: trips.map { $0.id.uuidString.lowercased() }, token: accessToken)
        try await markChildrenDeleted(table: "trip_expenses", parentColumn: "trip_id", parentIDs: trips.map { $0.id.uuidString.lowercased() }, token: accessToken)
        try await upsert("trip_stops", rows: stops, token: accessToken)
        try await upsert("trip_expenses", rows: expenses, token: accessToken)
        try await syncAccountAssets(email: normalizedEmail, accessToken: accessToken)
        // Record the exact versions acknowledged by the cloud only after every
        // entity and child-row upload succeeded. A failed partial sync must not
        // advance the baseline and hide a later two-sided edit.
        for agency in agencies { agency.syncBaseUpdatedAt = agency.updateAt }
        for customer in customers { customer.syncBaseUpdatedAt = customer.updateAt }
        for trip in trips { trip.syncBaseUpdatedAt = trip.updatedAt ?? trip.createdAt }
        try context.save()
        summary.trips = trips.count
        summary.uploaded = agencies.count + customers.count + trips.count
        return summary
    }

    @MainActor
    static func resolveConflict(_ conflict: CloudSyncConflict, keepRemote: Bool, context: ModelContext) throws {
        guard conflict.ownerScope == DataOwnership.activeScope else {
            throw SyncError.response("当前账号无权处理此同步冲突。")
        }
        if conflict.tableName == "customers", conflict.isRemoteDeletion, keepRemote,
           SyncEditRegistry.isEditing(table: "customers", id: conflict.recordID, scope: conflict.ownerScope) {
            throw SyncError.response("客户资料仍在打开，请先退出客户资料页面，再接受删除。")
        }
        guard let data = conflict.remotePayloadJSON.data(using: .utf8),
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SyncError.response("冲突版本无法读取，记录仍保留，请重新同步后再试。")
        }
        let recordID = conflict.recordID
        let ownerScope = conflict.ownerScope
        let deletionKey = "\(conflict.tableName):\(recordID.lowercased())"
        switch conflict.tableName {
        case "travel_agencies":
            let descriptor = FetchDescriptor<TravelAgency>(predicate: #Predicate { $0.uuid == recordID && $0.ownerScope == ownerScope })
            if let model = try context.fetch(descriptor).first {
                if conflict.isRemoteDeletion && keepRemote {
                    context.delete(model)
                } else if conflict.isRemoteDeletion {
                    model.updateAt = .now
                    model.syncBaseUpdatedAt = conflict.remoteUpdatedAt
                } else if keepRemote {
                    model.agencyCode = string(row, "agency_code") ?? model.agencyCode
                    model.name = string(row, "name") ?? model.name
                    model.contactPerson = string(row, "contact_person") ?? ""
                    model.phone = string(row, "phone") ?? ""
                    model.officeAddress = string(row, "office_address") ?? ""
                    model.updateAt = conflict.remoteUpdatedAt
                }
                model.syncBaseUpdatedAt = conflict.remoteUpdatedAt
            } else if conflict.isLocalDeletion && keepRemote,
                      let id = string(row, "id") {
                let model = TravelAgency(uuid: id, agencyCode: string(row, "agency_code") ?? "",
                                         name: string(row, "name") ?? "", contactPerson: string(row, "contact_person") ?? "",
                                         phone: string(row, "phone") ?? "", officeAddress: string(row, "office_address") ?? "",
                                         createdAt: date(row, "created_at") ?? conflict.remoteUpdatedAt,
                                         updateAt: conflict.remoteUpdatedAt, syncBaseUpdatedAt: conflict.remoteUpdatedAt)
                model.ownerScope = ownerScope
                context.insert(model)
            }
        case "customers":
            let descriptor = FetchDescriptor<Custumer>(predicate: #Predicate { $0.uuid == recordID && $0.ownerScope == ownerScope })
            if let model = try context.fetch(descriptor).first {
                if conflict.isRemoteDeletion && keepRemote {
                    context.delete(model)
                } else if conflict.isRemoteDeletion {
                    model.updateAt = .now
                    model.syncBaseUpdatedAt = conflict.remoteUpdatedAt
                } else if keepRemote {
                    apply(row, to: model, updatedAt: conflict.remoteUpdatedAt)
                }
                model.syncBaseUpdatedAt = conflict.remoteUpdatedAt
            } else if conflict.isLocalDeletion && keepRemote,
                      let id = string(row, "id") {
                let model = Custumer(uuid: id, name: string(row, "name") ?? "", email: string(row, "email") ?? "",
                                     avatarUrl: string(row, "avatar_url") ?? "", csource: string(row, "source") ?? "",
                                     type: integer(row, "type") ?? 1, customerCategory: integer(row, "category") ?? 1,
                                     travelAgencyCode: string(row, "travel_agency_code") ?? "",
                                     travelAgencyName: string(row, "travel_agency_name") ?? "",
                                     languagePreference: string(row, "language_preference") ?? "zh-Hans",
                                     remark: string(row, "remark") ?? "", createdAt: date(row, "created_at") ?? conflict.remoteUpdatedAt,
                                     updateAt: conflict.remoteUpdatedAt, syncBaseUpdatedAt: conflict.remoteUpdatedAt)
                model.ownerScope = ownerScope
                context.insert(model)
            }
        case "trips":
            guard let id = UUID(uuidString: conflict.recordID) else {
                throw SyncError.response("行程冲突的记录编号无效，记录仍保留。")
            }
            let descriptor = FetchDescriptor<TripBookingRecord>(predicate: #Predicate { $0.id == id && $0.ownerScope == ownerScope })
            if let model = try context.fetch(descriptor).first {
                if conflict.isRemoteDeletion && keepRemote {
                    context.delete(model)
                } else if conflict.isRemoteDeletion {
                    model.updatedAt = .now
                    model.syncBaseUpdatedAt = conflict.remoteUpdatedAt
                } else if keepRemote {
                    apply(row, to: model, updatedAt: conflict.remoteUpdatedAt)
                }
                model.syncBaseUpdatedAt = conflict.remoteUpdatedAt
            } else if conflict.isLocalDeletion && keepRemote {
                let model = TripBookingRecord(form: tripForm(row, id: id))
                model.ownerScope = ownerScope
                model.createdAt = date(row, "created_at") ?? conflict.remoteUpdatedAt
                apply(row, to: model, updatedAt: conflict.remoteUpdatedAt)
                context.insert(model)
            }
        default:
            throw SyncError.response("暂不支持处理此类同步冲突，记录仍保留。")
        }
        if conflict.isLocalDeletion {
            let tombstoneDescriptor = FetchDescriptor<CloudSyncDeletion>(predicate: #Predicate { $0.key == deletionKey && $0.ownerScope == ownerScope })
            if let tombstone = try context.fetch(tombstoneDescriptor).first {
                if keepRemote {
                    context.delete(tombstone)
                } else {
                    tombstone.baseUpdatedAt = conflict.remoteUpdatedAt
                    tombstone.deletedAt = .now
                }
            }
        }
        context.delete(conflict)
        try context.save()
    }

    /// Reconciles account-owned image and profile JSON independently so a blank
    /// device never overwrites an existing cloud business card or payment method.
    static func syncAccountAssets(email: String, accessToken: String) async throws {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty else { return }
        let ownerID = try await currentUserID(accessToken: accessToken)
        let settings = try await fetchRows("user_settings", token: accessToken).first
        var update: [String: Any] = ["owner_id": ownerID]
        var downloadedAssets = false

        for asset in AccountAssetStore.Asset.allCases {
            let localData = AccountAssetStore.data(for: asset, email: normalizedEmail, namespace: .cloud)
            let localDate = AccountAssetStore.updatedAt(for: asset, email: normalizedEmail, namespace: .cloud)
            let cloudKey = asset.cloudColumn
            let remoteValue = settings?[cloudKey]
            let remoteData: Data? = {
                guard let remoteValue, !(remoteValue is NSNull), JSONSerialization.isValidJSONObject(remoteValue) || remoteValue is String || remoteValue is NSNumber else { return nil }
                return try? JSONSerialization.data(withJSONObject: remoteValue, options: [.fragmentsAllowed, .sortedKeys])
            }()
            let remoteDate = settings.flatMap { date($0, "\(cloudKey)_updated_at") }

            if let localData {
                let effectiveLocalDate = localDate ?? .now
                if localDate == nil {
                    AccountAssetStore.set(localData, for: asset, email: normalizedEmail, namespace: .cloud, updatedAt: effectiveLocalDate)
                }
                if remoteData == nil || remoteDate == nil || effectiveLocalDate >= remoteDate! {
                    guard var json = try? JSONSerialization.jsonObject(with: localData, options: [.fragmentsAllowed]) else {
                        throw SyncError.response("本机名片或收款方式数据无法读取，请重新保存后同步。")
                    }
                    try await uploadEmbeddedAccountImages(in: &json, asset: asset, ownerID: ownerID, token: accessToken)
                    update[cloudKey] = json
                    update["\(cloudKey)_updated_at"] = iso(effectiveLocalDate)
                } else if let remoteData {
                    let localJSON = try await hydrateAccountImages(in: remoteData, asset: asset, token: accessToken)
                    AccountAssetStore.set(localJSON, for: asset, email: normalizedEmail, namespace: .cloud, updatedAt: remoteDate)
                    downloadedAssets = true
                }
            } else if let remoteData, let remoteDate {
                let localJSON = try await hydrateAccountImages(in: remoteData, asset: asset, token: accessToken)
                AccountAssetStore.set(localJSON, for: asset, email: normalizedEmail, namespace: .cloud, updatedAt: remoteDate)
                downloadedAssets = true
            }
        }

        if update.count > 1 {
            try await upsertUserSettings(update, token: accessToken)
        }
        if downloadedAssets {
            await MainActor.run {
                NotificationCenter.default.post(name: .accountAssetsDidSync, object: nil)
            }
        }
    }

    /// Converts legacy base64 image fields into private Storage objects before
    /// writing account JSON. The image is retained locally and the remote JSON
    /// receives only a durable object path.
    private static func uploadEmbeddedAccountImages(in value: inout Any, asset: AccountAssetStore.Asset, ownerID: String, token: String) async throws {
        guard var root = value as? [String: Any] else { return }
        switch asset {
        case .businessCard:
            if let base64 = root["portraitData"] as? String, !base64.isEmpty {
                let path = accountAssetPath(root["portraitPath"] as? String,
                                            fallback: "\(ownerID)/business-card/portrait.jpg",
                                            ownerID: ownerID)
                try await uploadImage(base64: base64, path: path, token: token)
                root["portraitPath"] = path
                root.removeValue(forKey: "portraitData")
            } else if let path = root["portraitPath"] as? String, !path.isEmpty,
                      !isAccountAssetPath(path, ownerID: ownerID) {
                throw SyncError.response("名片头像属于另一个云端账号，请先在原账号同步图片，或重新选择头像。")
            }
            if var codes = root["qrCodes"] as? [[String: Any]] {
                for index in codes.indices {
                    let id = (codes[index]["id"] as? String) ?? UUID().uuidString.lowercased()
                    let base64 = codes[index]["imageData"] as? String
                    let hasLocalImage = base64?.isEmpty == false
                    let existingPath = codes[index]["imagePath"] as? String
                    if !hasLocalImage, let existingPath, !existingPath.isEmpty,
                       !isAccountAssetPath(existingPath, ownerID: ownerID) {
                        throw SyncError.response("名片二维码属于另一个云端账号，请先在原账号同步图片，或重新选择二维码。")
                    }
                    guard let base64, !base64.isEmpty else { continue }
                    let path = accountAssetPath(existingPath,
                                               fallback: "\(ownerID)/business-card/qr/\(id).jpg",
                                               ownerID: ownerID)
                    try await uploadImage(base64: base64, path: path, token: token)
                    codes[index]["id"] = id
                    codes[index]["imagePath"] = path
                    codes[index].removeValue(forKey: "imageData")
                }
                root["qrCodes"] = codes
            }
        case .paymentMethods:
            if var methods = root["methods"] as? [[String: Any]] {
                for index in methods.indices {
                    let id = (methods[index]["id"] as? String) ?? UUID().uuidString.lowercased()
                    let base64 = methods[index]["qrImageData"] as? String
                    let hasLocalImage = base64?.isEmpty == false
                    let existingPath = methods[index]["qrImagePath"] as? String
                    if !hasLocalImage, let existingPath, !existingPath.isEmpty,
                       !isAccountAssetPath(existingPath, ownerID: ownerID) {
                        throw SyncError.response("收款二维码属于另一个云端账号，请先在原账号同步图片，或重新选择二维码。")
                    }
                    guard let base64, !base64.isEmpty else { continue }
                    let path = accountAssetPath(existingPath,
                                               fallback: "\(ownerID)/payment-methods/\(id).jpg",
                                               ownerID: ownerID)
                    try await uploadImage(base64: base64, path: path, token: token)
                    methods[index]["id"] = id
                    methods[index]["qrImagePath"] = path
                    methods[index].removeValue(forKey: "qrImageData")
                }
                root["methods"] = methods
            }
        }
        value = root
    }

    private static func accountAssetPath(_ candidate: String?, fallback: String, ownerID: String) -> String {
        guard let candidate, !candidate.isEmpty else { return fallback }
        if isAccountAssetPath(candidate, ownerID: ownerID) { return candidate }
        return fallback
    }

    private static func isAccountAssetPath(_ path: String, ownerID: String) -> Bool {
        let components = path.split(separator: "/")
        return components.count >= 2
            && components.first.map { String($0) } == ownerID
            && components.allSatisfy { $0 != "." && $0 != ".." }
    }

    /// Downloads referenced private images into the existing on-device Codable
    /// models. This keeps older app UI code and offline access working unchanged.
    private static func hydrateAccountImages(in data: Data, asset: AccountAssetStore.Asset, token: String) async throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else { return data }
        switch asset {
        case .businessCard:
            if let path = root["portraitPath"] as? String, !path.isEmpty {
                root["portraitData"] = try await downloadImage(path: path, token: token).base64EncodedString()
            }
            if var codes = root["qrCodes"] as? [[String: Any]] {
                for index in codes.indices {
                    if let path = codes[index]["imagePath"] as? String, !path.isEmpty {
                        codes[index]["imageData"] = try await downloadImage(path: path, token: token).base64EncodedString()
                    }
                }
                root["qrCodes"] = codes
            }
        case .paymentMethods:
            if var methods = root["methods"] as? [[String: Any]] {
                for index in methods.indices {
                    if let path = methods[index]["qrImagePath"] as? String, !path.isEmpty {
                        methods[index]["qrImageData"] = try await downloadImage(path: path, token: token).base64EncodedString()
                    }
                }
                root["methods"] = methods
            }
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.fragmentsAllowed, .sortedKeys])
    }

    private static func uploadImage(base64: String, path: String, token: String) async throws {
        guard let source = Data(base64Encoded: base64), let image = UIImage(data: source), let jpeg = image.jpegData(compressionQuality: 0.88) else {
            throw SyncError.response("名片或收款二维码图片无法读取，请重新选择后同步。")
        }
        let normalizedImage: Data
        if max(image.size.width, image.size.height) > 2048 {
            let scale = 2048 / max(image.size.width, image.size.height)
            let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            normalizedImage = renderer.jpegData(withCompressionQuality: 0.82) { _ in
                image.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        } else {
            normalizedImage = jpeg
        }
        var request = storageRequest(path: path, token: token, operation: "object")
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = normalizedImage
        try await validateStorageResponse(request)
    }

    private static func downloadImage(path: String, token: String) async throws -> Data {
        var request = storageRequest(path: path, token: token, operation: "object/authenticated")
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SyncError.response("云端图片读取失败，请检查 Storage 数据库迁移和私有存储权限。")
        }
        return data
    }

    private static func storageRequest(path: String, token: String, operation: String) -> URLRequest {
        let encodedPath = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        var request = URLRequest(url: SupabaseAuthClient.endpoint(path: "/storage/v1/\(operation)/account-assets/\(encodedPath)"))
        request.setValue(SupabaseAuthClient.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func validateStorageResponse(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = payload?["message"] as? String ?? payload?["error"] as? String
            throw SyncError.response("云端图片上传失败：\(detail ?? "请检查 Storage 迁移和权限配置。")")
        }
    }

    private static func upsertUserSettings(_ row: [String: Any], token: String) async throws {
        var components = URLComponents(url: SupabaseAuthClient.endpoint(path: "/rest/v1/user_settings"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "owner_id")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(SupabaseAuthClient.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: row, options: [.fragmentsAllowed])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = body?["message"] as? String ?? body?["details"] as? String
                ?? "云端数据表未就绪或权限配置不正确（user_settings）。"
            throw SyncError.response(message)
        }
    }

    @MainActor
    private static func conflictExists(table: String, id: String, scope: String, context: ModelContext) -> Bool {
        let key = "\(scope)|\(table)|\(id.lowercased())"
        let descriptor = FetchDescriptor<CloudSyncConflict>(predicate: #Predicate { $0.key == key && $0.ownerScope == scope })
        return (try? context.fetchCount(descriptor)) ?? 0 > 0
    }

    @MainActor
    private static func storeConflict(table: String, id: String, scope: String, localUpdatedAt: Date,
                                      remoteUpdatedAt: Date, row: [String: Any], context: ModelContext,
                                      isLocalDeletion: Bool = false, isRemoteDeletion: Bool = false) throws {
        guard JSONSerialization.isValidJSONObject(row) else {
            throw SyncError.response("发现双端修改，但无法保存云端版本；本机和云端数据均未覆盖。")
        }
        let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        guard let payload = String(data: data, encoding: .utf8) else {
            throw SyncError.response("发现双端修改，但无法保存云端版本；本机和云端数据均未覆盖。")
        }
        context.insert(CloudSyncConflict(tableName: table, recordID: id, ownerScope: scope,
                                         localUpdatedAt: localUpdatedAt, remoteUpdatedAt: remoteUpdatedAt,
                                         remotePayloadJSON: payload, isLocalDeletion: isLocalDeletion,
                                         isRemoteDeletion: isRemoteDeletion))
    }

    @MainActor
    private static func pullAndMerge(context: ModelContext, token: String, scope: String) async throws -> Int {
        var changed = 0
        let agencies = try context.fetch(FetchDescriptor<TravelAgency>(predicate: #Predicate { $0.ownerScope == scope }))
        let customers = try context.fetch(FetchDescriptor<Custumer>(predicate: #Predicate { $0.ownerScope == scope }))
        let trips = try context.fetch(FetchDescriptor<TripBookingRecord>(predicate: #Predicate { $0.ownerScope == scope }))
        let cloudAgencies = try await fetchRows("travel_agencies", token: token)
        let cloudCustomers = try await fetchRows("customers", token: token)
        let cloudTrips = try await fetchRows("trips", token: token)
        let agencyMap = Dictionary(uniqueKeysWithValues: agencies.map { ($0.uuid.lowercased(), $0) })
        var customerMap = Dictionary(uniqueKeysWithValues: customers.map { ($0.uuid.lowercased(), $0) })
        var tripMap = Dictionary(uniqueKeysWithValues: trips.map { ($0.id.uuidString.lowercased(), $0) })
        var customerIDsToRefresh: Set<String> = []
        var tripIDsToRefresh: Set<String> = []

        for row in cloudAgencies {
            guard let id = string(row, "id"), let remoteDate = date(row, "updated_at") else { continue }
            if conflictExists(table: "travel_agencies", id: id, scope: scope, context: context) { continue }
            if isDeleted(row) {
                if let local = agencyMap[id.lowercased()] {
                    let localChanged = local.syncBaseUpdatedAt.map { local.updateAt > $0 } ?? true
                    let remoteChanged = local.syncBaseUpdatedAt.map { remoteDate > $0 } ?? true
                    if localChanged && remoteChanged {
                        try storeConflict(table: "travel_agencies", id: id, scope: scope, localUpdatedAt: local.updateAt,
                                          remoteUpdatedAt: remoteDate, row: row, context: context, isRemoteDeletion: true)
                        continue
                    }
                    if remoteDate >= local.updateAt { context.delete(local); changed += 1 }
                }
                continue
            }
            if let local = agencyMap[id.lowercased()] {
                if let baseline = local.syncBaseUpdatedAt, local.updateAt > baseline, remoteDate > baseline {
                    try storeConflict(table: "travel_agencies", id: id, scope: scope, localUpdatedAt: local.updateAt,
                                      remoteUpdatedAt: remoteDate, row: row, context: context)
                    continue
                }
                guard remoteDate >= local.updateAt else { continue }
                local.agencyCode = string(row, "agency_code") ?? local.agencyCode
                local.name = string(row, "name") ?? local.name
                local.contactPerson = string(row, "contact_person") ?? ""
                local.phone = string(row, "phone") ?? ""
                local.officeAddress = string(row, "office_address") ?? ""
                local.updateAt = remoteDate
                local.syncBaseUpdatedAt = remoteDate
            } else {
                let agency = TravelAgency(uuid: id, agencyCode: string(row, "agency_code") ?? "", name: string(row, "name") ?? "", contactPerson: string(row, "contact_person") ?? "", phone: string(row, "phone") ?? "", officeAddress: string(row, "office_address") ?? "", createdAt: date(row, "created_at") ?? remoteDate, updateAt: remoteDate, syncBaseUpdatedAt: remoteDate)
                agency.ownerScope = scope
                context.insert(agency)
            }
            changed += 1
        }

        for row in cloudCustomers {
            guard let id = string(row, "id"), let remoteDate = date(row, "updated_at") else { continue }
            if conflictExists(table: "customers", id: id, scope: scope, context: context) { continue }
            if isDeleted(row) {
                if let local = customerMap[id.lowercased()] {
                    // Keep a local customer model until the user explicitly
                    // accepts the remote delete. The detail/edit stack may be
                    // holding this SwiftData object even when its fields have
                    // not changed yet; deleting it here can terminate the app.
                    try storeConflict(table: "customers", id: id, scope: scope, localUpdatedAt: local.updateAt,
                                      remoteUpdatedAt: remoteDate, row: row, context: context, isRemoteDeletion: true)
                }
                continue
            }
            if let local = customerMap[id.lowercased()] {
                if let baseline = local.syncBaseUpdatedAt, local.updateAt > baseline, remoteDate > baseline {
                    try storeConflict(table: "customers", id: id, scope: scope, localUpdatedAt: local.updateAt,
                                      remoteUpdatedAt: remoteDate, row: row, context: context)
                    continue
                }
                guard remoteDate >= local.updateAt else { continue }
                apply(row, to: local, updatedAt: remoteDate)
            } else {
                let local = Custumer(uuid: id, name: string(row, "name") ?? "", email: string(row, "email") ?? "", avatarUrl: string(row, "avatar_url") ?? "", csource: string(row, "source") ?? "", type: integer(row, "type") ?? 1, customerCategory: integer(row, "category") ?? 1, travelAgencyCode: string(row, "travel_agency_code") ?? "", travelAgencyName: string(row, "travel_agency_name") ?? "", languagePreference: string(row, "language_preference") ?? "zh-Hans", remark: string(row, "remark") ?? "", createdAt: date(row, "created_at") ?? remoteDate, updateAt: remoteDate, syncBaseUpdatedAt: remoteDate)
                local.ownerScope = scope
                context.insert(local)
                customerMap[id.lowercased()] = local
            }
            customerIDsToRefresh.insert(id)
            changed += 1
        }

        for row in cloudTrips {
            guard let idText = string(row, "id"), let id = UUID(uuidString: idText), let remoteDate = date(row, "updated_at") else { continue }
            if conflictExists(table: "trips", id: idText, scope: scope, context: context) { continue }
            if isDeleted(row) {
                if let local = tripMap[idText.lowercased()] {
                    let localUpdatedAt = local.updatedAt ?? local.createdAt
                    let localChanged = local.syncBaseUpdatedAt.map { localUpdatedAt > $0 } ?? true
                    let remoteChanged = local.syncBaseUpdatedAt.map { remoteDate > $0 } ?? true
                    if localChanged && remoteChanged {
                        try storeConflict(table: "trips", id: idText, scope: scope, localUpdatedAt: localUpdatedAt,
                                          remoteUpdatedAt: remoteDate, row: row, context: context, isRemoteDeletion: true)
                        continue
                    }
                    if remoteDate >= localUpdatedAt { context.delete(local); changed += 1 }
                }
                continue
            }
            if let local = tripMap[idText.lowercased()] {
                let localUpdatedAt = local.updatedAt ?? local.createdAt
                if let baseline = local.syncBaseUpdatedAt, localUpdatedAt > baseline, remoteDate > baseline {
                    try storeConflict(table: "trips", id: idText, scope: scope, localUpdatedAt: localUpdatedAt,
                                      remoteUpdatedAt: remoteDate, row: row, context: context)
                    continue
                }
                guard remoteDate >= (local.updatedAt ?? local.createdAt) else { continue }
                apply(row, to: local, updatedAt: remoteDate)
            } else {
                let local = TripBookingRecord(form: tripForm(row, id: id))
                local.ownerScope = scope
                local.createdAt = date(row, "created_at") ?? remoteDate
                apply(row, to: local, updatedAt: remoteDate)
                context.insert(local)
                tripMap[idText.lowercased()] = local
            }
            tripIDsToRefresh.insert(idText.lowercased())
            changed += 1
        }

        if !customerIDsToRefresh.isEmpty {
            let allContacts = try await fetchRows("customer_contacts", token: token)
            let allAddresses = try await fetchRows("customer_addresses", token: token)
            for customerID in customerIDsToRefresh {
                guard let customer = customerMap[customerID.lowercased()] else { continue }
                let scopedCustomerID = customerID.lowercased()
                customer.connecttype.forEach { context.delete($0) }; customer.connecttype = []
                customer.addresses.forEach { context.delete($0) }; customer.addresses = []
                var seenContacts = Set<String>()
                for row in allContacts where string(row, "customer_id").map({ $0.lowercased() == scopedCustomerID }) == true && !isDeleted(row) {
                    let type = string(row, "contact_type") ?? ""
                    let value = string(row, "value") ?? ""
                    let key = "\(type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                    guard seenContacts.insert(key).inserted else { continue }
                    context.insert(Connect(connectlable: type, connecttype: value, isDefault: boolean(row, "is_default"), customer: customer))
                }
                var seenAddresses = Set<String>()
                for row in allAddresses where string(row, "customer_id").map({ $0.lowercased() == scopedCustomerID }) == true && !isDeleted(row) {
                    let label = string(row, "label") ?? ""
                    let address = string(row, "address") ?? ""
                    let key = "\(label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                    guard seenAddresses.insert(key).inserted else { continue }
                    context.insert(Address(addlable: label, addresses: address, isDefault: boolean(row, "is_default"), customer: customer))
                }
            }
        }

        if !tripIDsToRefresh.isEmpty {
            let remoteStops = try await fetchRows("trip_stops", token: token)
            let remoteExpenses = try await fetchRows("trip_expenses", token: token)
            for tripID in tripIDsToRefresh {
                guard let trip = tripMap[tripID] else { continue }
                let stops = remoteStops.filter { string($0, "trip_id")?.lowercased() == tripID && !isDeleted($0) }.sorted { (integer($0, "position") ?? 0) < (integer($1, "position") ?? 0) }.compactMap { string($0, "address") }
                trip.locationStops = stops
                let expenses: [TripExpenseAdjustment] = remoteExpenses.filter { string($0, "trip_id")?.lowercased() == tripID && !isDeleted($0) }.sorted { (integer($0, "position") ?? 0) < (integer($1, "position") ?? 0) }.map {
                    TripExpenseAdjustment(id: UUID(uuidString: string($0, "id") ?? "") ?? UUID(), isAddition: boolean($0, "is_addition"), title: string($0, "title") ?? "", amount: number($0, "amount") ?? 0)
                }
                trip.expenseAdjustments = expenses
            }
        }
        try context.save()
        return changed
    }

    @MainActor
    private static func deduplicateCustomerChildren(context: ModelContext, scope: String) throws {
        let customers = try context.fetch(FetchDescriptor<Custumer>(predicate: #Predicate { $0.ownerScope == scope }))
        let conflicts = try context.fetch(FetchDescriptor<CloudSyncConflict>(predicate: #Predicate { $0.ownerScope == scope && $0.tableName == "customers" }))
        let blockedCustomerIDs = Set(conflicts.map { $0.recordID.lowercased() })
        for customer in customers {
            guard !blockedCustomerIDs.contains(customer.uuid.lowercased()) else { continue }
            var seenContacts = Set<String>()
            var uniqueContacts: [Connect] = []
            for contact in customer.connecttype {
                let key = "\(contact.connectlable.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(contact.connecttype.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                if seenContacts.insert(key).inserted {
                    uniqueContacts.append(contact)
                } else {
                    if contact.isDefault, let existingIndex = uniqueContacts.firstIndex(where: {
                        "\($0.connectlable.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\($0.connecttype.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())" == key
                    }) {
                        uniqueContacts[existingIndex].isDefault = true
                    }
                    context.delete(contact)
                }
            }
            if !uniqueContacts.isEmpty {
                let defaultIndex = uniqueContacts.firstIndex(where: \.isDefault) ?? 0
                for index in uniqueContacts.indices { uniqueContacts[index].isDefault = index == defaultIndex }
            }
            customer.connecttype = uniqueContacts

            var seenAddresses = Set<String>()
            var uniqueAddresses: [Address] = []
            for address in customer.addresses {
                let key = "\(address.addlable.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\(address.addresses.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
                if seenAddresses.insert(key).inserted {
                    uniqueAddresses.append(address)
                } else {
                    if address.isDefault, let existingIndex = uniqueAddresses.firstIndex(where: {
                        "\($0.addlable.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())|\($0.addresses.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())" == key
                    }) {
                        uniqueAddresses[existingIndex].isDefault = true
                    }
                    context.delete(address)
                }
            }
            if !uniqueAddresses.isEmpty {
                let defaultIndex = uniqueAddresses.firstIndex(where: \.isDefault) ?? 0
                for index in uniqueAddresses.indices { uniqueAddresses[index].isDefault = index == defaultIndex }
            }
            customer.addresses = uniqueAddresses
        }
        try context.save()
    }

    private static func currentUserID(accessToken: String) async throws -> String {
        var request = URLRequest(url: SupabaseAuthClient.endpoint(path: "/auth/v1/user"))
        request.httpMethod = "GET"
        request.setValue(SupabaseAuthClient.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw SyncError.response("无法验证云端账号，请重新登录后重试。")
        }
        return id
    }

    private static func fetchRows(_ table: String, token: String) async throws -> [[String: Any]] {
        var components = URLComponents(url: SupabaseAuthClient.endpoint(path: "/rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "select", value: "*")]
        var allRows: [[String: Any]] = []
        let pageSize = 1000
        var offset = 0
        while true {
            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            request.setValue(SupabaseAuthClient.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("items", forHTTPHeaderField: "Range-Unit")
            request.setValue("\(offset)-\(offset + pageSize - 1)", forHTTPHeaderField: "Range")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw SyncError.response(body?["message"] as? String ?? "云端数据表未就绪或权限配置不正确（\(table)）。")
            }
            let rows = (try JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
            allRows.append(contentsOf: rows)
            if rows.count < pageSize { break }
            offset += pageSize
        }
        return allRows
    }

    private static func patchDeleted(_ deletion: CloudSyncDeletion, token: String) async throws {
        var components = URLComponents(url: SupabaseAuthClient.endpoint(path: "/rest/v1/\(deletion.tableName)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(deletion.recordID)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue(SupabaseAuthClient.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["deleted_at": iso(deletion.deletedAt), "updated_at": iso(deletion.deletedAt)])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw SyncError.response(body?["message"] as? String ?? "云端删除记录同步失败。")
        }
    }

    private static func markChildrenDeleted(table: String, parentColumn: String, parentIDs: [String], token: String) async throws {
        for parentID in parentIDs {
            var components = URLComponents(url: SupabaseAuthClient.endpoint(path: "/rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: parentColumn, value: "eq.\(parentID)"),
                URLQueryItem(name: "deleted_at", value: "is.null")
            ]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "PATCH"
            request.setValue(SupabaseAuthClient.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["deleted_at": iso(.now), "updated_at": iso(.now)])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                throw SyncError.response(body?["message"] as? String ?? "云端子记录同步失败（\(table)）。")
            }
        }
    }

    private static func apply(_ row: [String: Any], to customer: Custumer, updatedAt: Date) {
        customer.name = string(row, "name") ?? customer.name
        customer.email = string(row, "email") ?? ""
        customer.avatarUrl = string(row, "avatar_url") ?? ""
        customer.csource = string(row, "source") ?? ""
        customer.type = integer(row, "type") ?? 1
        customer.customerCategory = integer(row, "category") ?? 1
        customer.travelAgencyCode = string(row, "travel_agency_code") ?? ""
        customer.travelAgencyName = string(row, "travel_agency_name") ?? ""
        customer.languagePreference = string(row, "language_preference") ?? "zh-Hans"
        customer.remark = string(row, "remark") ?? ""
        customer.updateAt = updatedAt
        customer.syncBaseUpdatedAt = updatedAt
    }

    private static func apply(_ row: [String: Any], to trip: TripBookingRecord, updatedAt: Date) {
        trip.serviceType = string(row, "service_type") ?? trip.serviceType
        trip.orderSource = string(row, "order_source") ?? trip.orderSource
        trip.travelAgencyCode = string(row, "travel_agency_code") ?? ""
        trip.travelAgencyName = string(row, "travel_agency_name") ?? ""
        trip.customerUUID = string(row, "customer_id")
        trip.customerName = string(row, "customer_name") ?? ""
        trip.customerContact = string(row, "customer_contact") ?? ""
        trip.customerCount = string(row, "customer_count") ?? "1"
        trip.customerStuff = string(row, "customer_stuff") ?? "0"
        trip.appointmentDate = date(row, "appointment_date") ?? trip.appointmentDate
        trip.appointmentTime = date(row, "appointment_time") ?? trip.appointmentTime
        trip.locationStart = string(row, "location_start") ?? ""
        trip.locationEnd = string(row, "location_end") ?? ""
        trip.flightInfo = string(row, "flight_info") ?? ""
        trip.flightDate = date(row, "flight_date") ?? trip.flightDate
        trip.flightDepartureTime = string(row, "flight_departure_time")
        trip.flightEstimatedArrivalTime = string(row, "flight_estimated_arrival_time")
        trip.flightArrivalTerminal = string(row, "flight_arrival_terminal")
        trip.flightBaggageCarousel = string(row, "flight_baggage_carousel")
        trip.memo = string(row, "memo") ?? ""
        trip.price = number(row, "price") ?? 0
        trip.tip = number(row, "tip") ?? 0
        trip.isPaid = boolean(row, "is_paid")
        trip.isCompleted = boolean(row, "is_completed")
        trip.isCancelled = boolean(row, "is_cancelled")
        trip.reminderEnabled = boolean(row, "reminder_enabled")
        trip.reminderDateTime = date(row, "reminder_at")
        trip.hasSecondReminder = boolean(row, "has_second_reminder")
        trip.secondReminderDateTime = date(row, "second_reminder_at")
        trip.updatedAt = updatedAt
        trip.syncBaseUpdatedAt = updatedAt
    }

    private static func tripForm(_ row: [String: Any], id: UUID) -> NewTripFormModel {
        var form = NewTripFormModel()
        form.id = id
        form.serviceType = string(row, "service_type") ?? "接机"
        form.orderSource = string(row, "order_source") ?? "普通客户"
        form.travelAgencyCode = string(row, "travel_agency_code") ?? ""
        form.travelAgencyName = string(row, "travel_agency_name") ?? ""
        form.customerName = string(row, "customer_name") ?? ""
        form.selectedCustomerUUID = string(row, "customer_id")
        form.custemerConnect = string(row, "customer_contact") ?? ""
        form.customerCount = string(row, "customer_count") ?? "1"
        form.customerStuff = string(row, "customer_stuff") ?? "0"
        form.appointmentDate = date(row, "appointment_date") ?? .now
        form.appointmentTime = date(row, "appointment_time") ?? .now
        form.locationStart = string(row, "location_start") ?? ""
        form.locationEnd = string(row, "location_end") ?? ""
        form.flightInfo = string(row, "flight_info") ?? ""
        form.flightdate = date(row, "flight_date") ?? .now
        form.flightDepartureTime = string(row, "flight_departure_time") ?? ""
        form.flightEstimatedArrivalTime = string(row, "flight_estimated_arrival_time") ?? ""
        form.flightArrivalTerminal = string(row, "flight_arrival_terminal") ?? ""
        form.flightBaggageCarousel = string(row, "flight_baggage_carousel") ?? ""
        form.TripMemo = string(row, "memo") ?? ""
        form.TripPrice = number(row, "price") ?? 0
        form.isPaid = boolean(row, "is_paid")
        form.reminderEnabled = boolean(row, "reminder_enabled")
        form.reminderDateTime = date(row, "reminder_at") ?? .now
        form.hasSecondReminder = boolean(row, "has_second_reminder")
        form.secondReminderDateTime = date(row, "second_reminder_at") ?? .now
        return form
    }

    private static func isDeleted(_ row: [String: Any]) -> Bool { row["deleted_at"] != nil && !(row["deleted_at"] is NSNull) }
    private static func string(_ row: [String: Any], _ key: String) -> String? { row[key] as? String }
    private static func integer(_ row: [String: Any], _ key: String) -> Int? { (row[key] as? NSNumber)?.intValue }
    private static func number(_ row: [String: Any], _ key: String) -> Double? { (row[key] as? NSNumber)?.doubleValue }
    private static func boolean(_ row: [String: Any], _ key: String) -> Bool { (row[key] as? NSNumber)?.boolValue ?? false }
    private static func date(_ row: [String: Any], _ key: String) -> Date? {
        guard let text = row[key] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        if let value = formatter.date(from: text) { return value }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    private static func upsert(_ table: String, rows: [[String: Any]], token: String) async throws {
        guard !rows.isEmpty else { return }
        var components = URLComponents(url: SupabaseAuthClient.endpoint(path: "/rest/v1/\(table)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(SupabaseAuthClient.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: rows, options: [.fragmentsAllowed])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = body?["message"] as? String ?? body?["details"] as? String
                ?? "云端数据表未就绪或权限配置不正确（\(table)）。"
            throw SyncError.response(message)
        }
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func nullable<T>(_ value: T?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }

    private static func stableUUID(_ value: String) -> String {
        let bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])).uuidString.lowercased()
    }
}
