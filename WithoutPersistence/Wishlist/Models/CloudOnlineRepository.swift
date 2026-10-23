import Foundation
import UIKit

/// Direct, account-bound PostgREST access for the online-only edition.
/// Unlike `SupabaseDataSync`, this client has no local queue or retry storage:
/// a mutation is successful only after Supabase returns a 2xx response.
enum CloudOnlineRepository {
    enum Table: String {
        case customers
        case travelAgencies = "travel_agencies"
        case customerContacts = "customer_contacts"
        case customerAddresses = "customer_addresses"
        case trips
        case tripStops = "trip_stops"
        case tripExpenses = "trip_expenses"
        case userSettings = "user_settings"

        var ownerColumn: String { "owner_id" }

        var primaryKey: String {
            self == .userSettings ? "owner_id" : "id"
        }
    }

    enum AccountAsset: String {
        case businessCard = "business_card_data"
        case paymentMethods = "wallet_payment_methods"

        var updatedAtColumn: String { "\(rawValue)_updated_at" }
    }

    struct Account: Equatable {
        let id: String
        let email: String
    }

    struct CustomerRecord: Identifiable {
        let id: String
        let name: String
        let email: String
        let avatarURL: String
        let source: String
        let type: Int
        let category: Int
        let travelAgencyCode: String
        let travelAgencyName: String
        let languagePreference: String
        let remark: String
        let contacts: [ContactRecord]
        let addresses: [AddressRecord]

    }

    struct TravelAgencyRecord: Decodable, Identifiable {
        let id: String
        let agencyCode: String
        let name: String
        let contactPerson: String
        let phone: String
        let officeAddress: String
        let createdAt: String

        var creationDate: Date {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt) ?? .now
        }

        enum CodingKeys: String, CodingKey {
            case id, name, phone
            case agencyCode = "agency_code"
            case contactPerson = "contact_person"
            case officeAddress = "office_address"
            case createdAt = "created_at"
        }
    }

    struct CustomerTripRecord: Decodable, Identifiable {
        let id: String
        let customerID: String?
        let customerName: String
        let serviceType: String
        let appointmentDate: String
        let locationEnd: String
        let price: Double
        let tip: Double
        let isPaid: Bool
        let isCompleted: Bool
        let isCancelled: Bool
        let currencyCode: String

        var contribution: Double { price + tip }

        enum CodingKeys: String, CodingKey {
            case id, price, tip
            case customerID = "customer_id"
            case customerName = "customer_name"
            case serviceType = "service_type"
            case appointmentDate = "appointment_date"
            case locationEnd = "location_end"
            case isPaid = "is_paid"
            case isCompleted = "is_completed"
            case isCancelled = "is_cancelled"
            case currencyCode = "currency_code"
        }
    }

    struct CustomerListTripRecord: Decodable, Identifiable {
        let id: String
        let customerID: String?
        let customerName: String
        let price: Double
        let tip: Double
        let isPaid: Bool
        let isCancelled: Bool
        let currencyCode: String
        let expenses: [TripExpenseRecord]

        var netIncome: Double {
            price + tip + expenses.reduce(0) { total, expense in
                total + (expense.isAddition ? abs(expense.amount) : -abs(expense.amount))
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, price, tip, expenses
            case customerID = "customer_id"
            case customerName = "customer_name"
            case isPaid = "is_paid"
            case isCancelled = "is_cancelled"
            case currencyCode = "currency_code"
        }
    }

    struct TripStopRecord: Decodable, Identifiable {
        let id: String
        let tripID: String
        let position: Int
        let address: String
        enum CodingKeys: String, CodingKey {
            case id, position, address
            case tripID = "trip_id"
        }
    }

    struct TripExpenseRecord: Decodable, Identifiable {
        let id: String
        let tripID: String
        let position: Int
        let isAddition: Bool
        let title: String
        let amount: Double
        enum CodingKeys: String, CodingKey {
            case id, position, title, amount
            case tripID = "trip_id"
            case isAddition = "is_addition"
        }
    }

    struct CloudTripRecord: Identifiable {
        let id: String
        let serviceType: String
        let orderSource: String
        let travelAgencyCode: String
        let travelAgencyName: String
        let customerID: String?
        let customerName: String
        let customerContact: String
        let customerCount: String
        let customerStuff: String
        let appointmentDate: String
        let appointmentTime: String
        let locationStart: String
        let locationEnd: String
        let flightInfo: String
        let flightDate: String
        let flightDepartureTime: String?
        let flightEstimatedArrivalTime: String?
        let flightArrivalTerminal: String?
        let flightBaggageCarousel: String?
        let flightSelectionSnapshot: SavedFlightSelection?
        let memo: String
        let price: Double
        let tip: Double
        let isPaid: Bool
        let isCompleted: Bool
        let isCancelled: Bool
        let reminderEnabled: Bool
        let reminderAt: String?
        let hasSecondReminder: Bool
        let secondReminderAt: String?
        let currencyCode: String
        let createdAt: String
        let stops: [TripStopRecord]
        let expenses: [TripExpenseRecord]

    }

    private struct TripRow: Decodable {
        let id: String
        let serviceType: String
        let orderSource: String
        let travelAgencyCode: String
        let travelAgencyName: String
        let customerID: String?
        let customerName: String
        let customerContact: String
        let customerCount: String
        let customerStuff: String
        let appointmentDate: String
        let appointmentTime: String
        let locationStart: String
        let locationEnd: String
        let flightInfo: String
        let flightDate: String
        let flightDepartureTime: String?
        let flightEstimatedArrivalTime: String?
        let flightArrivalTerminal: String?
        let flightBaggageCarousel: String?
        let flightSelectionSnapshot: SavedFlightSelection?
        let memo: String
        let price: Double
        let tip: Double
        let isPaid: Bool
        let isCompleted: Bool
        let isCancelled: Bool
        let reminderEnabled: Bool
        let reminderAt: String?
        let hasSecondReminder: Bool
        let secondReminderAt: String?
        let currencyCode: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, memo, price, tip
            case serviceType = "service_type"
            case orderSource = "order_source"
            case travelAgencyCode = "travel_agency_code"
            case travelAgencyName = "travel_agency_name"
            case customerID = "customer_id"
            case customerName = "customer_name"
            case customerContact = "customer_contact"
            case customerCount = "customer_count"
            case customerStuff = "customer_stuff"
            case appointmentDate = "appointment_date"
            case appointmentTime = "appointment_time"
            case locationStart = "location_start"
            case locationEnd = "location_end"
            case flightInfo = "flight_info"
            case flightDate = "flight_date"
            case flightDepartureTime = "flight_departure_time"
            case flightEstimatedArrivalTime = "flight_estimated_arrival_time"
            case flightArrivalTerminal = "flight_arrival_terminal"
            case flightBaggageCarousel = "flight_baggage_carousel"
            case flightSelectionSnapshot = "flight_selection_snapshot"
            case isPaid = "is_paid"
            case isCompleted = "is_completed"
            case isCancelled = "is_cancelled"
            case reminderEnabled = "reminder_enabled"
            case reminderAt = "reminder_at"
            case hasSecondReminder = "has_second_reminder"
            case secondReminderAt = "second_reminder_at"
            case currencyCode = "currency_code"
            case createdAt = "created_at"
        }
    }

    private struct CurrencySettingsRow: Decodable {
        let currencyCode: String
        enum CodingKeys: String, CodingKey { case currencyCode = "currency_code" }
    }

    private struct CustomerRow: Decodable {
        let id: String
        let name: String
        let email: String
        let avatarURL: String
        let source: String
        let type: Int
        let category: Int
        let travelAgencyCode: String
        let travelAgencyName: String
        let languagePreference: String
        let remark: String

        enum CodingKeys: String, CodingKey {
            case id, name, email, source, type, category, remark
            case avatarURL = "avatar_url"
            case travelAgencyCode = "travel_agency_code"
            case travelAgencyName = "travel_agency_name"
            case languagePreference = "language_preference"
        }
    }

    struct ContactRecord: Decodable, Identifiable {
        let id: String
        let customerID: String
        let label: String
        let contactType: String
        let value: String
        let isDefault: Bool

        enum CodingKeys: String, CodingKey {
            case id, label, value
            case customerID = "customer_id"
            case contactType = "contact_type"
            case isDefault = "is_default"
        }
    }

    struct AddressRecord: Decodable, Identifiable {
        let id: String
        let customerID: String
        let label: String
        let address: String
        let isDefault: Bool

        enum CodingKeys: String, CodingKey {
            case id, label, address
            case customerID = "customer_id"
            case isDefault = "is_default"
        }
    }

    struct CustomerWrite: Encodable {
        let id: String
        let name: String
        let email: String
        let avatarURL: String
        let source: String
        let type: Int
        let category: Int
        let travelAgencyCode: String
        let travelAgencyName: String
        let languagePreference: String
        let remark: String
        let createdAt: Date

        func replacingAvatarURL(_ value: String) -> CustomerWrite {
            CustomerWrite(
                id: id, name: name, email: email, avatarURL: value, source: source,
                type: type, category: category, travelAgencyCode: travelAgencyCode,
                travelAgencyName: travelAgencyName, languagePreference: languagePreference,
                remark: remark, createdAt: createdAt
            )
        }

        enum CodingKeys: String, CodingKey {
            case id, name, email, type, category, remark, source
            case avatarURL = "avatar_url"
            case travelAgencyCode = "travel_agency_code"
            case travelAgencyName = "travel_agency_name"
            case languagePreference = "language_preference"
            case createdAt = "created_at"
        }
    }

    struct ContactWrite: Encodable {
        let id: String
        let label: String
        let contactType: String
        let value: String
        let isDefault: Bool

        enum CodingKeys: String, CodingKey {
            case id, label, value
            case contactType = "contact_type"
            case isDefault = "is_default"
        }
    }

    struct AddressWrite: Encodable {
        let id: String
        let label: String
        let address: String
        let isDefault: Bool

        enum CodingKeys: String, CodingKey {
            case id, label, address
            case isDefault = "is_default"
        }
    }

    enum RepositoryError: LocalizedError {
        case invalidAccount
        case accountChanged
        case invalidRows
        case unsupportedOperation
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidAccount:
                String(localized: "无法验证云端账号，请重新登录后重试。", locale: AppLanguageSettings.currentLocale)
            case .accountChanged:
                String(localized: "账号已切换，请重新打开页面后重试。", locale: AppLanguageSettings.currentLocale)
            case .invalidRows:
                String(localized: "云端资料格式无效，尚未保存。", locale: AppLanguageSettings.currentLocale)
            case .unsupportedOperation:
                String(localized: "此类云端资料不支持删除。", locale: AppLanguageSettings.currentLocale)
            case .requestFailed(let message):
                message
            }
        }
    }

    /// Reads only the authenticated account's rows. The server RLS remains the
    /// final boundary; this client-side check also prevents stale UI requests
    /// from continuing after an account switch.
    static func fetch(
        _ table: Table,
        account: Account,
        accessToken: String
    ) async throws -> Data {
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            let ownerFilter = URLQueryItem(name: table.ownerColumn, value: "eq.\(verifiedAccount.id)")
            var request = URLRequest(url: SupabaseAuthClient.endpoint(
                path: "/rest/v1/\(table.rawValue)",
                queryItems: [URLQueryItem(name: "select", value: "*")] + [ownerFilter]
            ))
            request.httpMethod = "GET"
            setAuthHeaders(on: &request, accessToken: accessToken)
            return try await perform(request, table: table)
        }
    }

    /// Loads the complete active customer directory from the current account.
    /// Child rows are joined in memory after all three requests succeed, so a
    /// partial response is never presented as a complete directory.
    static func fetchCustomers(
        account: Account,
        accessToken: String
    ) async throws -> [CustomerRecord] {
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            async let customersData = fetchRows(.customers, ownerID: verifiedAccount.id, accessToken: accessToken)
            async let contactsData = fetchRows(.customerContacts, ownerID: verifiedAccount.id, accessToken: accessToken)
            async let addressesData = fetchRows(.customerAddresses, ownerID: verifiedAccount.id, accessToken: accessToken)

            let decoder = JSONDecoder()
            let customers = try decoder.decode([CustomerRow].self, from: await customersData)
            let contacts = try decoder.decode([ContactRecord].self, from: await contactsData)
            let addresses = try decoder.decode([AddressRecord].self, from: await addressesData)
            let contactsByCustomer = Dictionary(grouping: contacts, by: \.customerID)
            let addressesByCustomer = Dictionary(grouping: addresses, by: \.customerID)

            return customers.map { customer in
                CustomerRecord(
                    id: customer.id,
                    name: customer.name,
                    email: customer.email,
                    avatarURL: customer.avatarURL,
                    source: customer.source,
                    type: customer.type,
                    category: customer.category,
                    travelAgencyCode: customer.travelAgencyCode,
                    travelAgencyName: customer.travelAgencyName,
                    languagePreference: customer.languagePreference,
                    remark: customer.remark,
                    contacts: contactsByCustomer[customer.id] ?? [],
                    addresses: addressesByCustomer[customer.id] ?? []
                )
            }
        }
    }

    static func fetchCustomerTrips(
        customerID: String,
        account: Account,
        accessToken: String
    ) async throws -> [CustomerTripRecord] {
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            guard let customerUUID = UUID(uuidString: customerID) else { throw RepositoryError.invalidRows }
            let query = [
                URLQueryItem(name: "select", value: "id,customer_id,customer_name,service_type,appointment_date,location_end,price,tip,is_paid,is_completed,is_cancelled,currency_code"),
                URLQueryItem(name: "owner_id", value: "eq.\(verifiedAccount.id)"),
                URLQueryItem(name: "customer_id", value: "eq.\(customerUUID.uuidString.lowercased())"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "order", value: "appointment_date.desc"),
                URLQueryItem(name: "limit", value: "1000")
            ]
            var request = URLRequest(url: SupabaseAuthClient.endpoint(path: "/rest/v1/trips", queryItems: query))
            request.httpMethod = "GET"
            setAuthHeaders(on: &request, accessToken: accessToken)
            let data = try await perform(request, table: .trips)
            return try JSONDecoder().decode([CustomerTripRecord].self, from: data)
        }
    }

    static func fetchCustomerListTrips(account: Account, accessToken: String) async throws -> [CustomerListTripRecord] {
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            let query = [
                URLQueryItem(name: "select", value: "id,customer_id,customer_name,price,tip,is_paid,is_cancelled,currency_code"),
                URLQueryItem(name: "owner_id", value: "eq.\(verifiedAccount.id)"),
                URLQueryItem(name: "deleted_at", value: "is.null"),
                URLQueryItem(name: "order", value: "appointment_date.desc"),
                URLQueryItem(name: "limit", value: "1000")
            ]
            var request = URLRequest(url: SupabaseAuthClient.endpoint(path: "/rest/v1/trips", queryItems: query))
            request.httpMethod = "GET"
            setAuthHeaders(on: &request, accessToken: accessToken)
            let tripRequest = request
            async let tripData = perform(tripRequest, table: .trips)
            async let expenseData = fetchRows(.tripExpenses, ownerID: verifiedAccount.id, accessToken: accessToken)
            let tripRows = try JSONDecoder().decode([CustomerListTripRow].self, from: await tripData)
            let expenses = try JSONDecoder().decode([TripExpenseRecord].self, from: await expenseData)
            let expensesByTrip = Dictionary(grouping: expenses, by: \.tripID)
            return tripRows.map { trip in
                CustomerListTripRecord(
                    id: trip.id, customerID: trip.customerID, customerName: trip.customerName,
                    price: trip.price, tip: trip.tip, isPaid: trip.isPaid, isCancelled: trip.isCancelled,
                    currencyCode: trip.currencyCode,
                    expenses: (expensesByTrip[trip.id] ?? []).sorted { $0.position < $1.position }
                )
            }
        }
    }

    private struct CustomerListTripRow: Decodable {
        let id: String
        let customerID: String?
        let customerName: String
        let price: Double
        let tip: Double
        let isPaid: Bool
        let isCancelled: Bool
        let currencyCode: String

        enum CodingKeys: String, CodingKey {
            case id, price, tip
            case customerID = "customer_id"
            case customerName = "customer_name"
            case isPaid = "is_paid"
            case isCancelled = "is_cancelled"
            case currencyCode = "currency_code"
        }
    }

    static func fetchTrips(account: Account, accessToken: String) async throws -> [CloudTripRecord] {
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            async let tripData = fetchRows(.trips, ownerID: verifiedAccount.id, accessToken: accessToken)
            async let stopData = fetchRows(.tripStops, ownerID: verifiedAccount.id, accessToken: accessToken)
            async let expenseData = fetchRows(.tripExpenses, ownerID: verifiedAccount.id, accessToken: accessToken)
            let decoder = JSONDecoder()
            let trips = try decoder.decode([TripRow].self, from: await tripData)
            let stops = try decoder.decode([TripStopRecord].self, from: await stopData)
            let expenses = try decoder.decode([TripExpenseRecord].self, from: await expenseData)
            let stopsByTrip = Dictionary(grouping: stops, by: \.tripID)
            let expensesByTrip = Dictionary(grouping: expenses, by: \.tripID)
            return trips.map { trip in
                CloudTripRecord(
                    id: trip.id, serviceType: trip.serviceType, orderSource: trip.orderSource,
                    travelAgencyCode: trip.travelAgencyCode, travelAgencyName: trip.travelAgencyName,
                    customerID: trip.customerID, customerName: trip.customerName,
                    customerContact: trip.customerContact, customerCount: trip.customerCount,
                    customerStuff: trip.customerStuff, appointmentDate: trip.appointmentDate,
                    appointmentTime: trip.appointmentTime, locationStart: trip.locationStart,
                    locationEnd: trip.locationEnd, flightInfo: trip.flightInfo,
                    flightDate: trip.flightDate, flightDepartureTime: trip.flightDepartureTime,
                    flightEstimatedArrivalTime: trip.flightEstimatedArrivalTime,
                    flightArrivalTerminal: trip.flightArrivalTerminal,
                    flightBaggageCarousel: trip.flightBaggageCarousel,
                    flightSelectionSnapshot: trip.flightSelectionSnapshot,
                    memo: trip.memo, price: trip.price, tip: trip.tip,
                    isPaid: trip.isPaid, isCompleted: trip.isCompleted, isCancelled: trip.isCancelled,
                    reminderEnabled: trip.reminderEnabled, reminderAt: trip.reminderAt,
                    hasSecondReminder: trip.hasSecondReminder, secondReminderAt: trip.secondReminderAt,
                    currencyCode: trip.currencyCode, createdAt: trip.createdAt,
                    stops: (stopsByTrip[trip.id] ?? []).sorted { $0.position < $1.position },
                    expenses: (expensesByTrip[trip.id] ?? []).sorted { $0.position < $1.position }
                )
            }
            .sorted { $0.appointmentDate > $1.appointmentDate }
        }
    }

    static func saveTrip(
        trip: [String: Any],
        stops: [[String: Any]],
        expenses: [[String: Any]],
        account: Account,
        accessToken: String
    ) async throws {
        try await withVerifiedAccount(account, token: accessToken) { _ in
            var request = URLRequest(url: SupabaseAuthClient.endpoint(path: "/rest/v1/rpc/save_online_trip"))
            request.httpMethod = "POST"
            setAuthHeaders(on: &request, accessToken: accessToken)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = ["p_trip": trip, "p_stops": stops, "p_expenses": expenses]
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
            _ = try await perform(request, table: .trips)
        }
    }

    static func deleteTrip(id: String, account: Account, accessToken: String) async throws {
        try await withVerifiedAccount(account, token: accessToken) { _ in
            var request = URLRequest(url: SupabaseAuthClient.endpoint(path: "/rest/v1/rpc/delete_online_trip"))
            request.httpMethod = "POST"
            setAuthHeaders(on: &request, accessToken: accessToken)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["p_trip_id": id])
            _ = try await perform(request, table: .trips)
        }
    }

    static func fetchTravelAgencies(account: Account, accessToken: String) async throws -> [TravelAgencyRecord] {
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            let data = try await fetchRows(.travelAgencies, ownerID: verifiedAccount.id, accessToken: accessToken)
            return try JSONDecoder().decode([TravelAgencyRecord].self, from: data)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    static func fetchCurrencyCode(account: Account, accessToken: String) async throws -> String {
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            let data = try await fetchRows(.userSettings, ownerID: verifiedAccount.id, accessToken: accessToken)
            let settings = try JSONDecoder().decode([CurrencySettingsRow].self, from: data).first
            return settings?.currencyCode.uppercased() ?? "USD"
        }
    }

    static func fetchAccountAsset(
        _ asset: AccountAsset,
        account: Account,
        accessToken: String
    ) async throws -> Data? {
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            let data = try await fetchRows(.userSettings, ownerID: verifiedAccount.id, accessToken: accessToken)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let value = rows.first?[asset.rawValue], !(value is NSNull) else { return nil }
            return try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        }
    }

    static func saveAccountAsset(
        _ data: Data,
        as asset: AccountAsset,
        account: Account,
        accessToken: String
    ) async throws {
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            guard var root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
                throw RepositoryError.invalidRows
            }
            let oldData = try await fetchAccountAsset(asset, account: verifiedAccount, accessToken: accessToken)
            let oldPaths: [String]
            if let oldData,
               let oldRoot = try? JSONSerialization.jsonObject(with: oldData) as? [String: Any] {
                oldPaths = assetImagePaths(in: oldRoot)
            } else {
                oldPaths = []
            }
            var uploadedPaths: [String] = []
            do {
                try await uploadImages(in: &root, asset: asset, account: verifiedAccount, accessToken: accessToken,
                                       uploadedPaths: &uploadedPaths)
                let row: [String: Any] = [
                    "owner_id": verifiedAccount.id,
                    asset.rawValue: root,
                    asset.updatedAtColumn: ISO8601DateFormatter().string(from: .now),
                    "updated_at": ISO8601DateFormatter().string(from: .now)
                ]
                try await upsert([row], into: .userSettings, account: verifiedAccount, accessToken: accessToken)
            } catch {
                for path in uploadedPaths {
                    try? await removeAccountAssetObject(path: path, account: verifiedAccount, accessToken: accessToken)
                }
                throw error
            }
            let newPaths = assetImagePaths(in: root)
            for path in oldPaths where !newPaths.contains(path) {
                try? await removeAccountAssetObject(path: path, account: verifiedAccount, accessToken: accessToken)
            }
        }
    }

    static func hydrateAccountAsset(
        _ data: Data,
        as asset: AccountAsset,
        account: Account,
        accessToken: String
    ) async throws -> Data {
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            guard var root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
                throw RepositoryError.invalidRows
            }
            try await hydrateImages(in: &root, asset: asset, account: verifiedAccount, accessToken: accessToken)
            return try JSONSerialization.data(withJSONObject: root, options: [.fragmentsAllowed, .sortedKeys])
        }
    }

    static func saveTravelAgency(
        id: String,
        agencyCode: String,
        name: String,
        contactPerson: String,
        phone: String,
        officeAddress: String,
        createdAt: Date,
        account: Account,
        accessToken: String
    ) async throws {
        guard UUID(uuidString: id) != nil else { throw RepositoryError.invalidRows }
        let formatter = ISO8601DateFormatter()
        let row: [String: Any] = [
            "id": id.lowercased(),
            "agency_code": String(agencyCode.prefix(64)),
            "name": String(name.prefix(160)),
            "contact_person": String(contactPerson.prefix(160)),
            "phone": String(phone.prefix(80)),
            "office_address": String(officeAddress.prefix(512)),
            "created_at": formatter.string(from: createdAt),
            "updated_at": formatter.string(from: .now),
            "deleted_at": NSNull()
        ]
        try await upsert([row], into: .travelAgencies, account: account, accessToken: accessToken)
    }

    /// Stores customer photos in a private account folder. A unique object name
    /// lets us keep the old avatar intact until the customer RPC commits.
    static func uploadCustomerAvatar(
        _ imageData: Data,
        customerID: String,
        account: Account,
        accessToken: String
    ) async throws -> String {
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            guard UUID(uuidString: customerID) != nil,
                  let image = UIImage(data: imageData),
                  let normalizedData = normalizedJPEG(image) else {
                throw RepositoryError.invalidRows
            }
            let path = "\(verifiedAccount.id)/customers/\(customerID.lowercased())/avatars/\(UUID().uuidString.lowercased()).jpg"
            var request = storageRequest(path: path, operation: "object", accessToken: accessToken)
            request.httpMethod = "POST"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.setValue("true", forHTTPHeaderField: "x-upsert")
            request.httpBody = normalizedData
            try await performStorage(request)
            return path
        }
    }

    static func downloadCustomerAvatar(
        path: String,
        account: Account,
        accessToken: String
    ) async throws -> Data {
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            guard isOwnedAssetPath(path, accountID: verifiedAccount.id) else { throw RepositoryError.invalidRows }
            var request = storageRequest(path: path, operation: "object/authenticated", accessToken: accessToken)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw RepositoryError.requestFailed(String(localized: "云端头像读取失败，请检查私有存储权限。", locale: AppLanguageSettings.currentLocale))
            }
            return data
        }
    }

    static func removeCustomerAvatar(
        path: String,
        account: Account,
        accessToken: String
    ) async throws {
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            guard isOwnedAssetPath(path, accountID: verifiedAccount.id) else { throw RepositoryError.invalidRows }
            var request = storageRequest(path: path, operation: "object", accessToken: accessToken)
            request.httpMethod = "DELETE"
            try await performStorage(request)
        }
    }

    static func authenticatedAccount(accessToken: String) async throws -> Account {
        try await currentAccount(token: accessToken)
    }

    /// Writes rows directly to the server and returns only after the server
    /// confirms success. `owner_id` is overwritten from the verified JWT user
    /// rather than accepted from caller-provided payloads.
    static func upsert(
        _ rows: [[String: Any]],
        into table: Table,
        account: Account,
        accessToken: String
    ) async throws {
        guard !rows.isEmpty else { return }
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            let normalizedRows = rows.map { row -> [String: Any] in
                var safeRow = row
                safeRow[table.ownerColumn] = verifiedAccount.id
                return safeRow
            }
            let url = SupabaseAuthClient.endpoint(
                path: "/rest/v1/\(table.rawValue)",
                queryItems: [URLQueryItem(name: "on_conflict", value: table.primaryKey)]
            )
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            setAuthHeaders(on: &request, accessToken: accessToken)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: normalizedRows, options: [.fragmentsAllowed])
            } catch {
                throw RepositoryError.invalidRows
            }
            _ = try await perform(request, table: table)
        }
    }

    /// Saves a customer and replaces its contact/address rows in one database
    /// transaction through the dedicated RPC. The SwiftData mirror should only
    /// be updated after this call succeeds.
    static func saveCustomer(
        _ customer: CustomerWrite,
        contacts: [ContactWrite],
        addresses: [AddressWrite],
        account: Account,
        accessToken: String
    ) async throws {
        try await withVerifiedAccount(account, token: accessToken) { _ in
            var request = URLRequest(url: SupabaseAuthClient.endpoint(path: "/rest/v1/rpc/save_online_customer"))
            request.httpMethod = "POST"
            setAuthHeaders(on: &request, accessToken: accessToken)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                request.httpBody = try encoder.encode(SaveCustomerRequest(
                    customer: customer,
                    contacts: contacts,
                    addresses: addresses
                ))
            } catch {
                throw RepositoryError.invalidRows
            }
            _ = try await perform(request, table: .customers)
        }
    }

    /// Soft-deletes a customer and its related rows together. The operation is
    /// committed only after the authenticated server accepts the whole change.
    static func deleteCustomer(
        id: String,
        account: Account,
        accessToken: String
    ) async throws {
        try await withVerifiedAccount(account, token: accessToken) { _ in
            var request = URLRequest(url: SupabaseAuthClient.endpoint(path: "/rest/v1/rpc/delete_online_customer"))
            request.httpMethod = "POST"
            setAuthHeaders(on: &request, accessToken: accessToken)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["p_customer_id": id])
            _ = try await perform(request, table: .customers)
        }
    }

    /// Soft-deletes a row online. No tombstone is written locally and no
    /// offline operation is retained if this request fails.
    static func softDelete(
        _ recordID: String,
        from table: Table,
        account: Account,
        accessToken: String
    ) async throws {
        guard table != .userSettings else { throw RepositoryError.unsupportedOperation }
        try await withVerifiedAccount(account, token: accessToken) { verifiedAccount in
            let query = [
                URLQueryItem(name: table.primaryKey, value: "eq.\(recordID)"),
                URLQueryItem(name: table.ownerColumn, value: "eq.\(verifiedAccount.id)")
            ]
            var request = URLRequest(url: SupabaseAuthClient.endpoint(path: "/rest/v1/\(table.rawValue)", queryItems: query))
            request.httpMethod = "PATCH"
            setAuthHeaders(on: &request, accessToken: accessToken)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            let timestamp = ISO8601DateFormatter().string(from: .now)
            request.httpBody = try JSONSerialization.data(withJSONObject: ["deleted_at": timestamp, "updated_at": timestamp])
            _ = try await perform(request, table: table)
        }
    }

    private static func withVerifiedAccount<T>(
        _ expectedAccount: Account,
        token: String,
        operation: (Account) async throws -> T
    ) async throws -> T {
        let current = try await currentAccount(token: token)
        guard current.id == expectedAccount.id,
              current.email.caseInsensitiveCompare(expectedAccount.email) == .orderedSame else {
            throw RepositoryError.accountChanged
        }
        let result = try await operation(current)
        let accountAfterRequest = try await currentAccount(token: token)
        guard accountAfterRequest.id == current.id else { throw RepositoryError.accountChanged }
        return result
    }

    private static func currentAccount(token: String) async throws -> Account {
        var request = URLRequest(url: SupabaseAuthClient.endpoint(path: "/auth/v1/user"))
        request.httpMethod = "GET"
        setAuthHeaders(on: &request, accessToken: token)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String,
              let email = json["email"] as? String else {
            throw RepositoryError.invalidAccount
        }
        return Account(id: id, email: email)
    }

    private static func perform(_ request: URLRequest, table: Table) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = body?["message"] as? String ?? body?["details"] as? String
            throw RepositoryError.requestFailed(
                detail ?? String(localized: "云端资料请求失败（%@）。", locale: AppLanguageSettings.currentLocale)
                    .replacingOccurrences(of: "%@", with: table.rawValue)
            )
        }
        return data
    }

    private static func fetchRows(
        _ table: Table,
        ownerID: String,
        accessToken: String
    ) async throws -> Data {
        var queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: table.ownerColumn, value: "eq.\(ownerID)"),
            URLQueryItem(name: "deleted_at", value: "is.null"),
            URLQueryItem(name: "order", value: table == .customers ? "updated_at.desc" : "\(table.primaryKey).asc"),
            URLQueryItem(name: "limit", value: "1000")
        ]
        if table != .customers, table != .customerContacts, table != .customerAddresses,
           table != .travelAgencies, table != .trips, table != .tripStops, table != .tripExpenses {
            queryItems.removeAll { $0.name == "deleted_at" }
        }
        var request = URLRequest(url: SupabaseAuthClient.endpoint(path: "/rest/v1/\(table.rawValue)", queryItems: queryItems))
        request.httpMethod = "GET"
        setAuthHeaders(on: &request, accessToken: accessToken)
        return try await perform(request, table: table)
    }

    private static func setAuthHeaders(on request: inout URLRequest, accessToken: String) {
        request.setValue(SupabaseAuthClient.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        SupabaseAuthClient.applyAccountDeviceHeader(to: &request)
    }

    private static func storageRequest(path: String, operation: String, accessToken: String) -> URLRequest {
        let segmentCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        let encodedPath = path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: segmentCharacters) ?? String($0)
        }.joined(separator: "/")
        var request = URLRequest(url: SupabaseAuthClient.endpoint(path: "/storage/v1/\(operation)/account-assets/\(encodedPath)"))
        setAuthHeaders(on: &request, accessToken: accessToken)
        return request
    }

    private static func performStorage(_ request: URLRequest) async throws {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = payload?["message"] as? String ?? payload?["error"] as? String
            throw RepositoryError.requestFailed(detail ?? String(localized: "云端图片保存失败，请检查 Storage 权限配置。", locale: AppLanguageSettings.currentLocale))
        }
    }

    private static func isOwnedAssetPath(_ path: String, accountID: String) -> Bool {
        isSafeOwnedStoragePath(path, accountID: accountID, minimumComponents: 5)
    }

    private static func normalizedJPEG(_ image: UIImage) -> Data? {
        let maxEdge = max(image.size.width, image.size.height)
        let scale = min(1, 2048 / maxEdge)
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.jpegData(withCompressionQuality: 0.84) { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func uploadImages(
        in root: inout [String: Any],
        asset: AccountAsset,
        account: Account,
        accessToken: String,
        uploadedPaths: inout [String]
    ) async throws {
        switch asset {
        case .businessCard:
            try await uploadImageField(root: &root, dataKey: "portraitData", pathKey: "portraitPath",
                                       folder: "business-card/portrait", account: account,
                                       accessToken: accessToken, uploadedPaths: &uploadedPaths)
            if var codes = root["qrCodes"] as? [[String: Any]] {
                for index in codes.indices {
                    let id = (codes[index]["id"] as? String) ?? UUID().uuidString.lowercased()
                    var code = codes[index]
                    try await uploadImageField(root: &code, dataKey: "imageData", pathKey: "imagePath",
                                               folder: "business-card/qr/\(id)", account: account,
                                               accessToken: accessToken, uploadedPaths: &uploadedPaths)
                    code["id"] = id
                    codes[index] = code
                }
                root["qrCodes"] = codes
            }
        case .paymentMethods:
            if var methods = root["methods"] as? [[String: Any]] {
                for index in methods.indices {
                    let id = (methods[index]["id"] as? String) ?? UUID().uuidString.lowercased()
                    var method = methods[index]
                    try await uploadImageField(root: &method, dataKey: "qrImageData", pathKey: "qrImagePath",
                                               folder: "payment-methods/\(id)", account: account,
                                               accessToken: accessToken, uploadedPaths: &uploadedPaths)
                    method["id"] = id
                    methods[index] = method
                }
                root["methods"] = methods
            }
        }
    }

    private static func uploadImageField(
        root: inout [String: Any],
        dataKey: String,
        pathKey: String,
        folder: String,
        account: Account,
        accessToken: String,
        uploadedPaths: inout [String]
    ) async throws {
        if let base64 = root[dataKey] as? String, !base64.isEmpty {
            guard let sourceData = Data(base64Encoded: base64),
                  let image = UIImage(data: sourceData),
                  let imageData = normalizedJPEG(image) else { throw RepositoryError.invalidRows }
            let path = "\(account.id)/\(folder)/\(UUID().uuidString.lowercased()).jpg"
            var request = storageRequest(path: path, operation: "object", accessToken: accessToken)
            request.httpMethod = "POST"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.setValue("true", forHTTPHeaderField: "x-upsert")
            request.httpBody = imageData
            try await performStorage(request)
            root[pathKey] = path
            root.removeValue(forKey: dataKey)
            uploadedPaths.append(path)
        } else if let path = root[pathKey] as? String, !path.isEmpty,
                  !isOwnedAccountAssetPath(path, accountID: account.id) {
            throw RepositoryError.requestFailed(String(localized: "图片属于另一个云端账号，请在原账号重新保存。", locale: AppLanguageSettings.currentLocale))
        }
    }

    private static func hydrateImages(
        in root: inout [String: Any],
        asset: AccountAsset,
        account: Account,
        accessToken: String
    ) async throws {
        switch asset {
        case .businessCard:
            try await hydrateImageField(root: &root, dataKey: "portraitData", pathKey: "portraitPath",
                                        account: account, accessToken: accessToken)
            if var codes = root["qrCodes"] as? [[String: Any]] {
                for index in codes.indices {
                    var code = codes[index]
                    try await hydrateImageField(root: &code, dataKey: "imageData", pathKey: "imagePath",
                                                account: account, accessToken: accessToken)
                    codes[index] = code
                }
                root["qrCodes"] = codes
            }
        case .paymentMethods:
            if var methods = root["methods"] as? [[String: Any]] {
                for index in methods.indices {
                    var method = methods[index]
                    try await hydrateImageField(root: &method, dataKey: "qrImageData", pathKey: "qrImagePath",
                                                account: account, accessToken: accessToken)
                    methods[index] = method
                }
                root["methods"] = methods
            }
        }
    }

    private static func hydrateImageField(
        root: inout [String: Any],
        dataKey: String,
        pathKey: String,
        account: Account,
        accessToken: String
    ) async throws {
        guard let path = root[pathKey] as? String, !path.isEmpty else { return }
        guard isOwnedAccountAssetPath(path, accountID: account.id) else { throw RepositoryError.invalidRows }
        var request = storageRequest(path: path, operation: "object/authenticated", accessToken: accessToken)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RepositoryError.requestFailed(String(localized: "云端图片读取失败，请检查私有存储权限。", locale: AppLanguageSettings.currentLocale))
        }
        root[dataKey] = data.base64EncodedString()
    }

    private static func removeAccountAssetObject(
        path: String,
        account: Account,
        accessToken: String
    ) async throws {
        guard isOwnedAccountAssetPath(path, accountID: account.id) else { throw RepositoryError.invalidRows }
        var request = storageRequest(path: path, operation: "object", accessToken: accessToken)
        request.httpMethod = "DELETE"
        try await performStorage(request)
    }

    private static func isOwnedAccountAssetPath(_ path: String, accountID: String) -> Bool {
        isSafeOwnedStoragePath(path, accountID: accountID, minimumComponents: 3)
    }

    private static func isSafeOwnedStoragePath(
        _ path: String,
        accountID: String,
        minimumComponents: Int
    ) -> Bool {
        guard UUID(uuidString: accountID) != nil else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let segmentCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        return components.count >= minimumComponents
            && components[0].lowercased() == accountID.lowercased()
            && components.allSatisfy { component in
                !component.isEmpty
                    && component != "."
                    && component != ".."
                    && component.unicodeScalars.allSatisfy(segmentCharacters.contains)
            }
    }

    private static func assetImagePaths(in root: [String: Any]) -> [String] {
        var paths: [String] = []
        if let path = root["portraitPath"] as? String { paths.append(path) }
        for key in ["qrCodes", "methods"] {
            guard let rows = root[key] as? [[String: Any]] else { continue }
            let pathKey = key == "qrCodes" ? "imagePath" : "qrImagePath"
            paths.append(contentsOf: rows.compactMap { $0[pathKey] as? String })
        }
        return paths
    }

    private struct SaveCustomerRequest: Encodable {
        let customer: CustomerWrite
        let contacts: [ContactWrite]
        let addresses: [AddressWrite]

        enum CodingKeys: String, CodingKey {
            case customer = "p_customer"
            case contacts = "p_contacts"
            case addresses = "p_addresses"
        }
    }
}
