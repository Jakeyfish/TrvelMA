import Foundation

/// Keeps profile assets in separate namespaces for device-only and cloud accounts.
/// Legacy email-scoped values are copied into the device namespace and retained
/// so an interrupted upgrade can be rolled back without losing user data.
enum AccountAssetStore {
    enum Asset: CaseIterable {
        case businessCard
        case paymentMethods

        var legacyKeyPrefix: String {
            switch self {
            case .businessCard: "business-card.v1."
            case .paymentMethods: "wallet.paymentMethods.v1."
            }
        }

        var legacyDatePrefix: String {
            switch self {
            case .businessCard: "business-card.cloudUpdatedAt.v1."
            case .paymentMethods: "wallet-payment-methods.cloudUpdatedAt.v1."
            }
        }

        var cloudColumn: String {
            switch self {
            case .businessCard: "business_card_data"
            case .paymentMethods: "wallet_payment_methods"
            }
        }
    }

    enum Namespace {
        case local
        case cloud
    }

    private static let defaults = UserDefaults.standard

    static func data(for asset: Asset, email: String, namespace: Namespace) -> Data? {
        defaults.data(forKey: key(for: asset, email: email, namespace: namespace))
    }

    static func updatedAt(for asset: Asset, email: String, namespace: Namespace) -> Date? {
        defaults.object(forKey: updatedAtKey(for: asset, email: email, namespace: namespace)) as? Date
    }

    static func set(_ data: Data?, for asset: Asset, email: String, namespace: Namespace, updatedAt: Date? = nil) {
        let dataKey = key(for: asset, email: email, namespace: namespace)
        let dateKey = updatedAtKey(for: asset, email: email, namespace: namespace)
        if let data {
            defaults.set(data, forKey: dataKey)
            defaults.set(updatedAt ?? .now, forKey: dateKey)
        } else {
            defaults.removeObject(forKey: dataKey)
            defaults.removeObject(forKey: dateKey)
        }
    }

    /// One-time, non-destructive migration of an old email-keyed asset to the
    /// current local account. Existing v2 data always takes precedence.
    static func migrateLegacyAssetsToLocal(email: String) {
        let normalizedEmail = normalize(email)
        guard !normalizedEmail.isEmpty else { return }

        for asset in Asset.allCases {
            let targetKey = key(for: asset, email: normalizedEmail, namespace: .local)
            let targetDateKey = updatedAtKey(for: asset, email: normalizedEmail, namespace: .local)
            let legacyKey = asset.legacyKeyPrefix + normalizedEmail
            let legacyDateKey = asset.legacyDatePrefix + normalizedEmail
            if defaults.data(forKey: targetKey) == nil, let legacyData = defaults.data(forKey: legacyKey) {
                defaults.set(legacyData, forKey: targetKey)
            }
            if defaults.object(forKey: targetDateKey) == nil,
               let legacyDate = defaults.object(forKey: legacyDateKey) as? Date {
                defaults.set(legacyDate, forKey: targetDateKey)
            }
        }
    }

    static func hasUnimportedLocalAssets(from localEmail: String, to cloudEmail: String) -> Bool {
        let source = normalize(localEmail)
        let target = normalize(cloudEmail)
        guard !source.isEmpty, !target.isEmpty else { return false }

        return Asset.allCases.contains { asset in
            guard data(for: asset, email: source, namespace: .local) != nil else { return false }
            let marker = importDateKey(for: asset, sourceEmail: source, targetEmail: target)
            guard let importedAt = defaults.object(forKey: marker) as? Date,
                  let changedAt = updatedAt(for: asset, email: source, namespace: .local) else { return true }
            return changedAt > importedAt
        }
    }

    /// Copies opted-in local assets only into empty cloud slots. Local source
    /// data remains intact, and an import timestamp prevents repeated prompts.
    static func importLocalAssetsToCloud(from localEmail: String, to cloudEmail: String) {
        let source = normalize(localEmail)
        let target = normalize(cloudEmail)
        guard !source.isEmpty, !target.isEmpty else { return }

        for asset in Asset.allCases {
            let marker = importDateKey(for: asset, sourceEmail: source, targetEmail: target)
            guard let sourceData = data(for: asset, email: source, namespace: .local) else { continue }
            if data(for: asset, email: target, namespace: .cloud) == nil {
                set(sourceData, for: asset, email: target, namespace: .cloud,
                    updatedAt: updatedAt(for: asset, email: source, namespace: .local))
            }
            defaults.set(Date.now, forKey: marker)
        }
    }

    static func removeLocalAssets(email: String) {
        let normalizedEmail = normalize(email)
        for asset in Asset.allCases {
            set(nil, for: asset, email: normalizedEmail, namespace: .local)
            defaults.removeObject(forKey: asset.legacyKeyPrefix + normalizedEmail)
            defaults.removeObject(forKey: asset.legacyDatePrefix + normalizedEmail)
        }
    }

    private static func key(for asset: Asset, email: String, namespace: Namespace) -> String {
        let account = normalize(email)
        switch namespace {
        case .local:
            let scope = DataOwnership.localScope(email: account)
            let localID = String(scope.dropFirst("local:".count))
            return "accountAssets.local.v2.\(localID).\(asset.storageName)"
        case .cloud:
            return "accountAssets.cloud.v2.\(account).\(asset.storageName)"
        }
    }

    private static func updatedAtKey(for asset: Asset, email: String, namespace: Namespace) -> String {
        key(for: asset, email: email, namespace: namespace) + ".updatedAt"
    }

    private static func importDateKey(for asset: Asset, sourceEmail: String, targetEmail: String) -> String {
        "accountAssets.localImportDate.v2.\(sourceEmail).\(targetEmail).\(asset.storageName)"
    }

    private static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension AccountAssetStore.Asset {
    var storageName: String {
        switch self {
        case .businessCard: "businessCard"
        case .paymentMethods: "paymentMethods"
        }
    }
}
