import Foundation
import Observation
import SwiftData

/// The single source of truth for models persisted by the app.
/// Keeping schema creation centralized lets account stores share identical
/// model definitions while using separate SQLite files.
enum AppDataSchema {
    static let modelTypes: [any PersistentModel.Type] = [
        TravelAgency.self,
        Custumer.self,
        Address.self,
        Connect.self,
        LoginInfo.self,
        ProfileInfo.self,
        LocalAccount.self,
        TripBookingRecord.self,
        CloudSyncDeletion.self,
        CloudSyncConflict.self
    ]

    static func makeContainer(named name: String, in directory: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema(modelTypes)
        let storeURL = directory.appendingPathComponent("\(name).store")
        let configuration = ModelConfiguration(name, schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    static var legacyDefaultStoreURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("default.store", isDirectory: false)
    }

    static func openLegacyDefaultContainerIfPresent() throws -> ModelContainer? {
        guard let url = legacyDefaultStoreURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        let schema = Schema(modelTypes)
        let configuration = ModelConfiguration("default", schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

/// Owns the two durable SwiftData stores and switches the app's active context
/// when the user changes between local and cloud modes.
@MainActor
@Observable
final class AppDataContainerManager {
    enum Mode: String {
        case local
        case cloud
    }

    private(set) var activeContainer: ModelContainer
    private(set) var activeMode: Mode
    private(set) var startupError: String?

    private(set) var localContainer: ModelContainer?
    private(set) var cloudContainer: ModelContainer?
    private let supportDirectory: URL

    init() {
        let fileManager = FileManager.default
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        supportDirectory = baseDirectory.appendingPathComponent("WishlistAccountStores", isDirectory: true)
        activeContainer = Self.makeFallbackContainer()
        activeMode = UserDefaults.standard.bool(forKey: "auth.session.isCloud") ? .cloud : .local
        retryStartup()
    }

    func activate(forCloudAccount isCloudAccount: Bool) {
        let targetMode: Mode = isCloudAccount ? .cloud : .local
        guard let target = isCloudAccount ? cloudContainer : localContainer else { return }
        activeMode = targetMode
        activeContainer = target
    }

    func importLocalAccountToCloud(fromLocalEmail: String, toCloudEmail: String) throws {
        guard let localContainer, let cloudContainer else {
            throw LegacyStoreMigrator.MigrationError.storesUnavailable
        }
        try LegacyStoreMigrator.importLocalRecordsToCloud(
            from: localContainer,
            into: cloudContainer,
            fromLocalEmail: fromLocalEmail,
            toCloudEmail: toCloudEmail
        )
        AccountAssetStore.importLocalAssetsToCloud(from: fromLocalEmail, to: toCloudEmail)
    }

    func retryStartup() {
        var stage = "准备本机资料目录"
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            stage = "创建本机资料库"
            let local = try AppDataSchema.makeContainer(named: "local", in: supportDirectory)
            stage = "创建云端资料缓存"
            let cloud = try AppDataSchema.makeContainer(named: "cloud", in: supportDirectory)

            // The completion marker is written only after both copies and their
            // integrity checks succeed. The legacy source remains untouched.
            stage = "检查并迁移旧资料库"
            _ = try LegacyStoreMigrator.migrateLegacyDefaultStoreIfNeeded(toLocal: local, toCloud: cloud)

            localContainer = local
            cloudContainer = cloud
            startupError = nil
            activate(forCloudAccount: UserDefaults.standard.bool(forKey: "auth.session.isCloud"))
        } catch {
            startupError = "\(stage)失败：\(Self.diagnosticDescription(for: error))"
        }
    }

    private static func diagnosticDescription(for error: Error) -> String {
        let nsError = error as NSError
        let summary = "\(error.localizedDescription)（\(nsError.domain)，错误 \(nsError.code)）"
        guard let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError else { return summary }
        return "\(summary)；底层原因：\(underlying.localizedDescription)（\(underlying.domain)，错误 \(underlying.code)）"
    }

    private static func makeFallbackContainer() -> ModelContainer {
        let schema = Schema(AppDataSchema.modelTypes)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        // This is an error-only UI fallback. It never receives user-facing data
        // because RootView blocks normal app content while startupError exists.
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("Unable to create an in-memory SwiftData fallback container.")
        }
        return container
    }
}
