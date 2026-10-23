import Foundation
import Observation

@MainActor
@Observable
final class CloudAccountAssetModel {
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private var loadGeneration = 0

    func clearError() { errorMessage = nil }

    func beginAccountChange() {
        loadGeneration += 1
        errorMessage = nil
    }

    func setLoadError(_ message: String) { errorMessage = message }

    func load(_ asset: CloudOnlineRepository.AccountAsset, using auth: AuthViewModel) async -> Data? {
        loadGeneration += 1
        let generation = loadGeneration
        errorMessage = nil
        do {
            let (account, token) = try await session(using: auth)
            let fetched = try await CloudOnlineRepository.fetchAccountAsset(asset, account: account, accessToken: token)
            try ensureSameAccount(account, auth: auth)
            guard loadGeneration == generation else { return nil }
            guard let data = fetched else {
                return nil
            }
            let hydrated = try await CloudOnlineRepository.hydrateAccountAsset(
                data, as: asset, account: account, accessToken: token
            )
            try ensureSameAccount(account, auth: auth)
            guard loadGeneration == generation else { return nil }
            return hydrated
        } catch {
            if loadGeneration == generation { errorMessage = error.localizedDescription }
            return nil
        }
    }

    func save(
        _ data: Data,
        as asset: CloudOnlineRepository.AccountAsset,
        using auth: AuthViewModel
    ) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let requestedEmail = auth.currentEmail
        do {
            let (account, token) = try await session(using: auth)
            try await CloudOnlineRepository.saveAccountAsset(data, as: asset, account: account, accessToken: token)
            try ensureSameAccount(account, auth: auth)
            return true
        } catch {
            if auth.isCloudAccount,
               auth.currentEmail.caseInsensitiveCompare(requestedEmail) == .orderedSame {
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
