import Foundation
import Observation

extension Notification.Name {
    static let cloudTripsDidChange = Notification.Name("cloudTripsDidChange")
}

/// Ephemeral state and direct writes for cloud-only trip records.
@MainActor
@Observable
final class CloudTripDirectoryModel {
    private(set) var trips: [CloudOnlineRepository.CloudTripRecord] = []
    private(set) var customers: [CloudOnlineRepository.CustomerRecord] = []
    private(set) var agencies: [CloudOnlineRepository.TravelAgencyRecord] = []
    private(set) var currencyCode = "USD"
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private var loadedAccountID: String?
    private var reloadGeneration = 0

    func clearError() { errorMessage = nil }
    func setError(_ message: String) { errorMessage = message }

    func clearForAccountChange() {
        reloadGeneration += 1
        trips = []
        customers = []
        agencies = []
        currencyCode = "USD"
        loadedAccountID = nil
        errorMessage = nil
        isLoading = false
    }

    func reloadTrips(using auth: AuthViewModel) async {
        reloadGeneration += 1
        let generation = reloadGeneration
        isLoading = true
        errorMessage = nil
        defer { if reloadGeneration == generation { isLoading = false } }
        do {
            let (account, token) = try await session(using: auth)
            if loadedAccountID != account.id {
                trips = []
                customers = []
                agencies = []
                currencyCode = "USD"
                loadedAccountID = account.id
            }
            let rows = try await CloudOnlineRepository.fetchTrips(account: account, accessToken: token)
            try ensureSameAccount(account, auth: auth)
            let fetchedCurrencyCode = try await CloudOnlineRepository.fetchCurrencyCode(account: account, accessToken: token)
            try ensureSameAccount(account, auth: auth)
            guard reloadGeneration == generation else { return }
            trips = rows
            currencyCode = fetchedCurrencyCode
        } catch {
            if reloadGeneration == generation { errorMessage = error.localizedDescription }
        }
    }

    func reload(using auth: AuthViewModel) async {
        reloadGeneration += 1
        let generation = reloadGeneration
        isLoading = true
        errorMessage = nil
        defer { if reloadGeneration == generation { isLoading = false } }
        do {
            let (account, token) = try await session(using: auth)
            if loadedAccountID != account.id {
                trips = []
                customers = []
                agencies = []
                currencyCode = "USD"
                loadedAccountID = account.id
            }
            async let fetchedTrips = CloudOnlineRepository.fetchTrips(account: account, accessToken: token)
            async let fetchedCustomers = CloudOnlineRepository.fetchCustomers(account: account, accessToken: token)
            async let fetchedAgencies = CloudOnlineRepository.fetchTravelAgencies(account: account, accessToken: token)
            async let fetchedCurrencyCode = CloudOnlineRepository.fetchCurrencyCode(account: account, accessToken: token)
            let (tripRows, customerRows, agencyRows, tripCurrencyCode) = try await (
                fetchedTrips, fetchedCustomers, fetchedAgencies, fetchedCurrencyCode
            )
            try ensureSameAccount(account, auth: auth)
            guard reloadGeneration == generation else { return }
            trips = tripRows
            customers = customerRows
            agencies = agencyRows
            currencyCode = tripCurrencyCode
            loadedAccountID = account.id
        } catch {
            if reloadGeneration == generation { errorMessage = error.localizedDescription }
        }
    }

    func save(
        trip: [String: Any],
        stops: [[String: Any]],
        expenses: [[String: Any]],
        using auth: AuthViewModel
    ) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let (account, token) = try await session(using: auth)
            guard loadedAccountID == account.id else { throw CloudOnlineRepository.RepositoryError.accountChanged }
            try await CloudOnlineRepository.saveTrip(
                trip: trip, stops: stops, expenses: expenses,
                account: account, accessToken: token
            )
            try ensureSameAccount(account, auth: auth)
            await reload(using: auth)
            NotificationCenter.default.post(name: .cloudTripsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(id: String, using auth: AuthViewModel) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let (account, token) = try await session(using: auth)
            guard loadedAccountID == account.id else { throw CloudOnlineRepository.RepositoryError.accountChanged }
            try await CloudOnlineRepository.deleteTrip(id: id, account: account, accessToken: token)
            try ensureSameAccount(account, auth: auth)
            await reload(using: auth)
            NotificationCenter.default.post(name: .cloudTripsDidChange, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateStatus(
        for trip: CloudOnlineRepository.CloudTripRecord,
        isCompleted: Bool? = nil,
        isCancelled: Bool? = nil,
        isPaid: Bool? = nil,
        flightSelectionSnapshot: SavedFlightSelection? = nil,
        using auth: AuthViewModel
    ) async -> Bool {
        let row: [String: Any] = [
            "id": trip.id,
            "service_type": trip.serviceType,
            "order_source": trip.orderSource,
            "travel_agency_code": trip.travelAgencyCode,
            "travel_agency_name": trip.travelAgencyName,
            "customer_id": trip.customerID.map { $0 as Any } ?? NSNull(),
            "customer_name": trip.customerName,
            "customer_contact": trip.customerContact,
            "customer_count": trip.customerCount,
            "customer_stuff": trip.customerStuff,
            "appointment_date": trip.appointmentDate,
            "appointment_time": trip.appointmentTime,
            "location_start": trip.locationStart,
            "location_end": trip.locationEnd,
            "flight_info": trip.flightInfo,
            "flight_date": trip.flightDate,
            "flight_departure_time": trip.flightDepartureTime.map { $0 as Any } ?? NSNull(),
            "flight_estimated_arrival_time": trip.flightEstimatedArrivalTime.map { $0 as Any } ?? NSNull(),
            "flight_arrival_terminal": trip.flightArrivalTerminal.map { $0 as Any } ?? NSNull(),
            "flight_baggage_carousel": trip.flightBaggageCarousel.map { $0 as Any } ?? NSNull(),
            "flight_selection_snapshot": (flightSelectionSnapshot ?? trip.flightSelectionSnapshot).map { snapshot in
                (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))) ?? NSNull()
            } ?? NSNull(),
            "memo": trip.memo,
            "price": trip.price,
            "tip": trip.tip,
            "is_paid": isPaid ?? trip.isPaid,
            "is_completed": isCompleted ?? trip.isCompleted,
            "is_cancelled": isCancelled ?? trip.isCancelled,
            "reminder_enabled": trip.reminderEnabled,
            "reminder_at": trip.reminderAt.map { $0 as Any } ?? NSNull(),
            "has_second_reminder": trip.hasSecondReminder,
            "second_reminder_at": trip.secondReminderAt.map { $0 as Any } ?? NSNull(),
            "currency_code": trip.currencyCode,
            "created_at": trip.createdAt,
            "updated_at": ISO8601DateFormatter().string(from: .now),
            "deleted_at": NSNull()
        ]
        let stops = trip.stops.map { ["id": $0.id, "position": $0.position, "address": $0.address] as [String: Any] }
        let expenses = trip.expenses.map {
            ["id": $0.id, "position": $0.position, "is_addition": $0.isAddition, "title": $0.title, "amount": $0.amount] as [String: Any]
        }
        return await save(trip: row, stops: stops, expenses: expenses, using: auth)
    }

    private func session(using auth: AuthViewModel) async throws -> (CloudOnlineRepository.Account, String) {
        guard auth.isCloudAccount, !auth.currentEmail.isEmpty else {
            throw CloudOnlineRepository.RepositoryError.invalidAccount
        }
        var token = auth.cloudAccessToken
        if token == nil { token = await auth.refreshCloudAccessToken() }
        guard let token else { throw CloudOnlineRepository.RepositoryError.invalidAccount }
        let account = try await CloudOnlineRepository.authenticatedAccount(accessToken: token)
        try ensureSameAccount(account, auth: auth)
        return (account, token)
    }

    private func ensureSameAccount(_ account: CloudOnlineRepository.Account, auth: AuthViewModel) throws {
        guard auth.isCloudAccount,
              auth.currentEmail.caseInsensitiveCompare(account.email) == .orderedSame else {
            throw CloudOnlineRepository.RepositoryError.accountChanged
        }
    }
}
