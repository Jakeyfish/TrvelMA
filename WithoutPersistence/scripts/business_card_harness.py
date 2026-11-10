"""Extract production draft actions with deterministic cloud and account boundaries."""
from flight_editor_harness import block


def generate(root, source=None):
    if source is None: source = (root / 'Views/BusinessCardView.swift').read_text()
    models = '\n'.join(block(source, marker) for marker in ['private struct BusinessCardQR:', 'private struct BusinessCardDraft:'])
    models = models.replace('private struct ', 'struct ')
    methods = '\n'.join(block(source, marker) for marker in ['private var draftAccountKey:', 'private func loadPortrait(', 'private func applyQRCodeImage(', 'private func loadDraft()', 'private func saveDraft()'])
    text = '''import Foundation
import UIKit
@MainActor final class CardPhotoFixture: Equatable {
    nonisolated static func == (lhs: CardPhotoFixture, rhs: CardPhotoFixture) -> Bool { lhs === rhs }
    var loadHandler: (() async throws -> Data?)?
    func loadTransferable(type: Data.Type) async throws -> Data? { try await loadHandler?() }
}
struct CardEntitlementFixture { enum Edition { case cloud }; var edition: Edition = .cloud }
@MainActor final class CardAuthFixture {
    var currentEmail = "card-fixture@example.invalid"
    var isCloudAccount = true
    var serverEntitlement: CardEntitlementFixture? = CardEntitlementFixture()
}
@MainActor enum CardStoreFixture {
    enum Namespace { case cloud, local }
    enum Asset { case businessCard }
    static var values: [String: Data] = [:]
    static var migratedEmails: [String] = []
    static func key(email: String, namespace: Namespace) -> String { "\(namespace)|\(email.lowercased())" }
    static func migrateLegacyAssetsToLocal(email: String) { migratedEmails.append(email) }
    static func data(for asset: Asset, email: String, namespace: Namespace) -> Data? { values[key(email: email, namespace: namespace)] }
    static func set(_ data: Data, for asset: Asset, email: String, namespace: Namespace) { values[key(email: email, namespace: namespace)] = data }
}
@MainActor final class CardCloudFixture {
    var errorMessage: String?
    var loadCount = 0
    func setLoadError(_ message: String) { errorMessage = message }
    func clearError() { errorMessage = nil }
    var loadHandler: (() async -> Data?)?
    var saveHandler: ((Data) async -> Bool)?
    func load(_ asset: CardStoreFixture.Asset, using auth: CardAuthFixture) async -> Data? {
        loadCount += 1
        return await loadHandler?()
    }
    func save(_ data: Data, as asset: CardStoreFixture.Asset, using auth: CardAuthFixture) async -> Bool {
        await saveHandler?(data) ?? true
    }
}
'''
    text += models + '''
@MainActor final class CardDraftHarness {
    let auth = CardAuthFixture()
    let cloudAssetModel = CardCloudFixture()
    var draft = BusinessCardDraft()
    var persistedDraft: BusinessCardDraft? = BusinessCardDraft()
    var hasLoaded = true
    var draftLoadGeneration = 0
    var portraitPicker: CardPhotoFixture?
    var loadedDraftAccountKey: String? = "cloud|card-fixture@example.invalid"
    var assetNamespace: CardStoreFixture.Namespace { auth.isCloudAccount ? .cloud : .local }
    func localized(_ key: String) -> String { key }
'''+methods+'\n}\n'
    return text.replace('PhotosPickerItem', 'CardPhotoFixture').replace('BusinessCardDraft', 'CardDraftFixture').replace('BusinessCardQR', 'CardQRFixture').replace('AccountAssetStore', 'CardStoreFixture')
