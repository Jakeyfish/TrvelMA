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
    private var mutationGeneration = 0

    func clearError() { errorMessage = nil }
    func setError(_ message: String) { errorMessage = message }

    func clearForAccountChange() {
        reloadGeneration += 1
        mutationGeneration += 1
        isSaving = false
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
            cancelInactiveReminders(in: rows)
            currencyCode = fetchedCurrencyCode
            await refreshPendingReminders(in: rows, generation: generation)
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
            cancelInactiveReminders(in: tripRows)
            customers = customerRows
            agencies = agencyRows
            currencyCode = tripCurrencyCode
            loadedAccountID = account.id
            await refreshPendingReminders(in: tripRows, generation: generation)
        } catch {
            if reloadGeneration == generation { errorMessage = error.localizedDescription }
        }
    }

    private func refreshPendingReminders(in rows: [CloudOnlineRepository.CloudTripRecord], generation: Int) async {
        let locale = AppLanguageSettings.currentLocale
        let messages = rows.filter { !$0.isCompleted && !$0.isCancelled }.compactMap { trip -> (UUID, TripReminderMessage)? in
            guard let id = UUID(uuidString: trip.id) else { return nil }
            return (id, TripReminderMessage(trip: trip, locale: locale))
        }
        await TripReminderScheduler.refreshPendingMessages(Dictionary(uniqueKeysWithValues: messages), isCurrent: { self.reloadGeneration == generation })
    }

    private func cancelInactiveReminders(in rows: [CloudOnlineRepository.CloudTripRecord]) {
        for trip in rows where trip.isCompleted || trip.isCancelled {
            if let id = UUID(uuidString: trip.id) { TripReminderScheduler.cancel(tripID: id) }
        }
    }

    func save(
        trip: [String: Any],
        stops: [[String: Any]],
        expenses: [[String: Any]],
        using auth: AuthViewModel
    ) async -> Bool {
        guard !isSaving else { return false }
        let generation = mutationGeneration
        isSaving = true
        errorMessage = nil
        defer { if mutationGeneration == generation { isSaving = false } }
        do {
            let (account, token) = try await session(using: auth)
            guard mutationGeneration == generation else { return false }
            guard loadedAccountID == account.id else { throw CloudOnlineRepository.RepositoryError.accountChanged }
            try await CloudOnlineRepository.saveTrip(
                trip: trip, stops: stops, expenses: expenses,
                account: account, accessToken: token
            )
            guard mutationGeneration == generation else { return false }
            try ensureSameAccount(account, auth: auth)
            await reload(using: auth)
            guard mutationGeneration == generation else { return false }
            NotificationCenter.default.post(name: .cloudTripsDidChange, object: nil)
            return true
        } catch {
            if mutationGeneration == generation { errorMessage = error.localizedDescription }
            return false
        }
    }

    func settle(id: String, fare: Double, tip: Double, expenses: [[String: Any]], markPaid: Bool = true, using auth: AuthViewModel) async -> Bool {
        guard !isSaving else { return false }
        let generation = mutationGeneration
        isSaving = true
        errorMessage = nil
        defer { if mutationGeneration == generation { isSaving = false } }
        do {
            let (account, token) = try await session(using: auth)
            guard mutationGeneration == generation else { return false }
            guard loadedAccountID == account.id else { throw CloudOnlineRepository.RepositoryError.accountChanged }
            try await CloudOnlineRepository.saveSettlement(id: id, fare: fare, tip: tip, expenses: expenses, markPaid: markPaid,
                                                           account: account, accessToken: token)
            guard mutationGeneration == generation else { return false }
            try ensureSameAccount(account, auth: auth)
            if let index = trips.firstIndex(where: { $0.id == id }) {
                var cached = trips[index]
                cached.price = fare; cached.tip = tip
                if markPaid { cached.isPaid = true }
                cached.expenses = expenses.compactMap { row in
                    guard let expenseID = row["id"] as? String, let title = row["title"] as? String,
                          let amount = row["amount"] as? Double else { return nil }
                    return .init(id: expenseID, tripID: id, position: row["position"] as? Int ?? 0,
                                 isAddition: row["is_addition"] as? Bool ?? false, title: title, amount: amount)
                }
                trips[index] = cached
            }
            await reload(using: auth)
            guard mutationGeneration == generation else { return false }
            NotificationCenter.default.post(name: .cloudTripsDidChange, object: nil)
            return true
        } catch {
            if mutationGeneration == generation { errorMessage = error.localizedDescription }
            return false
        }
    }

    func delete(id: String, using auth: AuthViewModel) async -> Bool {
        guard !isSaving else { return false }
        let generation = mutationGeneration
        isSaving = true
        errorMessage = nil
        defer { if mutationGeneration == generation { isSaving = false } }
        do {
            let (account, token) = try await session(using: auth)
            guard mutationGeneration == generation else { return false }
            guard loadedAccountID == account.id else { throw CloudOnlineRepository.RepositoryError.accountChanged }
            try await CloudOnlineRepository.deleteTrip(id: id, account: account, accessToken: token)
            guard mutationGeneration == generation else { return false }
            try ensureSameAccount(account, auth: auth)
            // The server has confirmed deletion; a failed refresh must not restore the card.
            trips.removeAll { $0.id == id }
            await reload(using: auth)
            guard mutationGeneration == generation else { return false }
            NotificationCenter.default.post(name: .cloudTripsDidChange, object: nil)
            return true
        } catch {
            if mutationGeneration == generation { errorMessage = error.localizedDescription }
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
        let generation = mutationGeneration
        do {
            let (account, token) = try await session(using: auth)
            guard mutationGeneration == generation else { return false }
            guard loadedAccountID == account.id else { throw CloudOnlineRepository.RepositoryError.accountChanged }

            let expectedFlightContext = flightSelectionSnapshot == nil ? nil : trip.flightContextFields
            if let expectedFlightContext {
                guard trips.first(where: { $0.id == trip.id })?.flightContextFields == expectedFlightContext else {
                    throw CloudOnlineRepository.RepositoryError.tripChanged
                }
            }

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
                id: trip.id, fields: fields, expectedFlightContext: expectedFlightContext,
                account: account, accessToken: token
            )
            guard mutationGeneration == generation else { return false }
            try ensureSameAccount(account, auth: auth)
            if (isCompleted == true || isCancelled == true), let tripID = UUID(uuidString: trip.id) {
                TripReminderScheduler.cancel(tripID: tripID)
            }
            // Apply only acknowledged fields to the latest cached record. This also
            // keeps completion available to a settlement sheet if the reload fails.
            if let index = trips.firstIndex(where: { $0.id == trip.id }) {
                var cached = trips[index]
                if let isCompleted { cached.isCompleted = isCompleted }
                if let isCancelled { cached.isCancelled = isCancelled }
                if let isPaid { cached.isPaid = isPaid }
                if let flightSelectionSnapshot, cached.flightContextFields == expectedFlightContext {
                    cached.flightSelectionSnapshot = flightSelectionSnapshot
                    cached.flightDepartureTime = flightSelectionSnapshot.selected.departureTime
                    cached.flightEstimatedArrivalTime = flightSelectionSnapshot.selected.estimatedArrivalTime
                    cached.flightArrivalTerminal = flightSelectionSnapshot.selected.arrivalTerminal
                    cached.flightBaggageCarousel = flightSelectionSnapshot.selected.baggageCarousel
                }
                trips[index] = cached
            }
            await reload(using: auth)
            guard mutationGeneration == generation else { return false }
            NotificationCenter.default.post(name: .cloudTripsDidChange, object: nil)
            return true
        } catch {
            if mutationGeneration == generation { errorMessage = error.localizedDescription }
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
