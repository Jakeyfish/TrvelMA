import Foundation
import Observation

/// In-memory directory for online-only accounts. Mutations are sent directly
/// to Supabase and are never written to SwiftData or an offline queue.
@MainActor
@Observable
final class CloudTravelAgencyDirectoryModel {
    private(set) var agencies: [CloudOnlineRepository.TravelAgencyRecord] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private var loadedAccountID: String?
    private var reloadGeneration = 0

    func clearError() { errorMessage = nil }

    func clearForAccountChange() {
        reloadGeneration += 1
        agencies = []
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
                agencies = []
                loadedAccountID = account.id
            }
            let rows = try await CloudOnlineRepository.fetchTravelAgencies(account: account, accessToken: token)
            guard auth.isCloudAccount,
                  auth.currentEmail.caseInsensitiveCompare(account.email) == .orderedSame else {
                throw CloudOnlineRepository.RepositoryError.accountChanged
            }
            guard reloadGeneration == generation else { return }
            agencies = rows
            loadedAccountID = account.id
        } catch {
            if reloadGeneration == generation { errorMessage = error.localizedDescription }
        }
    }

    func save(
        id: String,
        agencyCode: String,
        name: String,
        contactPerson: String,
        phone: String,
        officeAddress: String,
        createdAt: Date,
        using auth: AuthViewModel
    ) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let (account, token) = try await session(using: auth)
            guard loadedAccountID == account.id else { throw CloudOnlineRepository.RepositoryError.accountChanged }
            try await CloudOnlineRepository.saveTravelAgency(
                id: id, agencyCode: agencyCode, name: name, contactPerson: contactPerson,
                phone: phone, officeAddress: officeAddress, createdAt: createdAt,
                account: account, accessToken: token
            )
            guard auth.isCloudAccount,
                  auth.currentEmail.caseInsensitiveCompare(account.email) == .orderedSame,
                  loadedAccountID == account.id else {
                throw CloudOnlineRepository.RepositoryError.accountChanged
            }
            await reload(using: auth)
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
            try await CloudOnlineRepository.softDelete(id, from: .travelAgencies, account: account, accessToken: token)
            guard auth.isCloudAccount,
                  auth.currentEmail.caseInsensitiveCompare(account.email) == .orderedSame,
                  loadedAccountID == account.id else {
                throw CloudOnlineRepository.RepositoryError.accountChanged
            }
            await reload(using: auth)
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
        guard auth.isCloudAccount,
              auth.currentEmail.caseInsensitiveCompare(account.email) == .orderedSame else {
            throw CloudOnlineRepository.RepositoryError.accountChanged
        }
        return (account, token)
    }
}
