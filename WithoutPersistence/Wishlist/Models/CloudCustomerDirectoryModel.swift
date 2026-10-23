import Foundation
import Observation

/// Ephemeral customer state for the online-only edition. This model never
/// touches SwiftData or stores a failed mutation for later replay.
@MainActor
@Observable
final class CloudCustomerDirectoryModel {
    private(set) var customers: [CloudOnlineRepository.CustomerRecord] = []
    private(set) var agencies: [CloudOnlineRepository.TravelAgencyRecord] = []
    private(set) var currencyCode = "USD"
    private(set) var tripsByCustomerID: [String: [CloudOnlineRepository.CustomerTripRecord]] = [:]
    private(set) var loadingTripCustomerIDs: Set<String> = []
    private(set) var tripErrorByCustomerID: [String: String] = [:]
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private var loadedAccountID: String?
    private var reloadGeneration = 0

    func clearError() {
        errorMessage = nil
    }

    func clearForAccountChange() {
        reloadGeneration += 1
        customers = []
        agencies = []
        currencyCode = "USD"
        tripsByCustomerID = [:]
        loadingTripCustomerIDs = []
        tripErrorByCustomerID = [:]
        loadedAccountID = nil
        errorMessage = nil
        isLoading = false
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
                customers = []
                agencies = []
                currencyCode = "USD"
                tripsByCustomerID = [:]
                loadingTripCustomerIDs = []
                tripErrorByCustomerID = [:]
                loadedAccountID = account.id
            }
            async let fetchedCustomers = CloudOnlineRepository.fetchCustomers(account: account, accessToken: token)
            async let fetchedAgencies = CloudOnlineRepository.fetchTravelAgencies(account: account, accessToken: token)
            async let fetchedCurrency = CloudOnlineRepository.fetchCurrencyCode(account: account, accessToken: token)
            let rows = try await fetchedCustomers
            let agencyRows = try? await fetchedAgencies
            let fetchedCurrencyCode = try? await fetchedCurrency
            guard auth.isCloudAccount,
                  auth.currentEmail.caseInsensitiveCompare(account.email) == .orderedSame else {
                throw CloudOnlineRepository.RepositoryError.accountChanged
            }
            guard reloadGeneration == generation else { return }
            customers = rows
            agencies = agencyRows ?? []
            currencyCode = fetchedCurrencyCode ?? "USD"
            loadedAccountID = account.id
        } catch {
            if reloadGeneration == generation { errorMessage = error.localizedDescription }
        }
    }

    func save(
        customer: CloudOnlineRepository.CustomerWrite,
        contacts: [CloudOnlineRepository.ContactWrite],
        addresses: [CloudOnlineRepository.AddressWrite],
        avatarData: Data?,
        using auth: AuthViewModel
    ) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let (account, token) = try await session(using: auth)
            guard loadedAccountID == account.id else {
                throw CloudOnlineRepository.RepositoryError.accountChanged
            }
            var savedCustomer = customer
            var uploadedAvatarPath: String?
            if let avatarData {
                uploadedAvatarPath = try await CloudOnlineRepository.uploadCustomerAvatar(
                    avatarData, customerID: customer.id, account: account, accessToken: token
                )
                savedCustomer = customer.replacingAvatarURL(uploadedAvatarPath!)
            }
            do {
                try await CloudOnlineRepository.saveCustomer(
                savedCustomer, contacts: contacts, addresses: addresses,
                account: account, accessToken: token
            )
            } catch {
                if let uploadedAvatarPath {
                    try? await CloudOnlineRepository.removeCustomerAvatar(
                        path: uploadedAvatarPath, account: account, accessToken: token
                    )
                }
                throw error
            }
            guard auth.isCloudAccount,
                  auth.currentEmail.caseInsensitiveCompare(account.email) == .orderedSame,
                  loadedAccountID == nil || loadedAccountID == account.id else {
                throw CloudOnlineRepository.RepositoryError.accountChanged
            }
            if let uploadedAvatarPath,
               let previousPath = customers.first(where: { $0.id == customer.id })?.avatarURL,
               previousPath != uploadedAvatarPath {
                try? await CloudOnlineRepository.removeCustomerAvatar(
                    path: previousPath, account: account, accessToken: token
                )
            }
            await reload(using: auth)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reloadTrips(for customerID: String, using auth: AuthViewModel) async {
        guard !loadingTripCustomerIDs.contains(customerID) else { return }
        loadingTripCustomerIDs.insert(customerID)
        defer { loadingTripCustomerIDs.remove(customerID) }
        do {
            tripErrorByCustomerID[customerID] = nil
            let (account, token) = try await session(using: auth)
            guard loadedAccountID == account.id,
                  customers.contains(where: { $0.id == customerID }) else {
                throw CloudOnlineRepository.RepositoryError.accountChanged
            }
            let trips = try await CloudOnlineRepository.fetchCustomerTrips(
                customerID: customerID, account: account, accessToken: token
            )
            guard auth.isCloudAccount,
                  auth.currentEmail.caseInsensitiveCompare(account.email) == .orderedSame,
                  loadedAccountID == account.id else {
                throw CloudOnlineRepository.RepositoryError.accountChanged
            }
            tripsByCustomerID[customerID] = trips
        } catch {
            tripErrorByCustomerID[customerID] = error.localizedDescription
        }
    }

    func loadAvatarData(path: String, using auth: AuthViewModel) async -> Data? {
        guard !path.isEmpty else { return nil }
        do {
            let (account, token) = try await session(using: auth)
            let data = try await CloudOnlineRepository.downloadCustomerAvatar(
                path: path, account: account, accessToken: token
            )
            guard auth.isCloudAccount,
                  auth.currentEmail.caseInsensitiveCompare(account.email) == .orderedSame else { return nil }
            return data
        } catch {
            return nil
        }
    }

    func delete(id: String, using auth: AuthViewModel) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let (account, token) = try await session(using: auth)
            guard loadedAccountID == account.id else {
                throw CloudOnlineRepository.RepositoryError.accountChanged
            }
            try await CloudOnlineRepository.deleteCustomer(id: id, account: account, accessToken: token)
            guard auth.isCloudAccount,
                  auth.currentEmail.caseInsensitiveCompare(account.email) == .orderedSame,
                  loadedAccountID == nil || loadedAccountID == account.id else {
                throw CloudOnlineRepository.RepositoryError.accountChanged
            }
            await reload(using: auth)
            return true
        } catch {
            if error.localizedDescription.localizedCaseInsensitiveContains("trip history") {
                errorMessage = String(localized: "该客户已有出行记录，不能删除。", locale: AppLanguageSettings.currentLocale)
            } else {
                errorMessage = error.localizedDescription
            }
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
        guard auth.isCloudAccount,
              auth.currentEmail.caseInsensitiveCompare(account.email) == .orderedSame else {
            throw CloudOnlineRepository.RepositoryError.accountChanged
        }
        return (account, token)
    }
}
