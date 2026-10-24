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
        do {
            let (account, token) = try await session(using: auth)
            guard loadedAccountID == account.id else { throw CloudOnlineRepository.RepositoryError.accountChanged }

            var fields: [String: Any] = ["updated_at": ISO8601DateFormatter().string(from: .now)]
            if let isCompleted { fields["is_completed"] = isCompleted }
            if let isCancelled { fields["is_cancelled"] = isCancelled }
            if let isPaid { fields["is_paid"] = isPaid }
            if let flightSelectionSnapshot {
                let selected = flightSelectionSnapshot.selected
                fields["flight_departure_time"] = selected.departureTime.map { $0 as Any } ?? NSNull()
                fields["flight_estimated_arrival_time"] = selected.estimatedArrivalTime.map { $0 as Any } ?? NSNull()
                fields["flight_arrival_terminal"] = selected.arrivalTerminal.map { $0 as Any } ?? NSNull()
                fields["flight_baggage_carousel"] = selected.baggageCarousel.map { $0 as Any } ?? NSNull()
                fields["flight_selection_snapshot"] =
                    (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(flightSelectionSnapshot))) ?? NSNull()
            }

            try await CloudOnlineRepository.updateTripFields(
                id: trip.id, fields: fields, account: account, accessToken: token
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
