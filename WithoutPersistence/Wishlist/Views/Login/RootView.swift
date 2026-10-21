//
//  RootView.swift
//  Wishlist
//
//  Created by Tony.W on 6/10/26.
//  Copyright © 2026 Apple. All rights reserved.
//


import SwiftUI
import SwiftData

//struct RootView: View {
//
//    @Environment(AuthViewModel.self)
//    private var auth
//
//    var body: some View {
//
//        if auth.isLoggedIn {
//
//            ContentView()
//
//        } else {
//
//            LoginView()
//        }
//    }
//}


struct RootView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppDataContainerManager.self) private var dataStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var cloudSyncStatus: CloudSyncStatus = .preparing
    @State private var isSyncing = false
    @State private var syncErrorMessage: String?
    @State private var pendingAssetSyncTask: Task<Void, Never>?
    @State private var assetSyncInProgress = false
    @State private var assetSyncNeedsAnotherPass = false
    @State private var cloudImportCounts: CloudImportCounts?
    @State private var pendingSyncConflicts: [CloudSyncConflict] = []
    @State private var isShowingSyncConflicts = false

    private var cloudImportConsentKey: String {
        "auth.cloud.initialLocalImportConsent.v1.\(auth.currentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private var hasCloudImportConsent: Bool {
        UserDefaults.standard.bool(forKey: cloudImportConsentKey)
    }

    private var storeTaskIdentity: String {
        [auth.isLoggedIn.description, auth.isCloudAccount.description, auth.currentEmail,
         dataStore.activeMode.rawValue, dataStore.startupError ?? ""].joined(separator: "|")
    }

    var body: some View {

        Group {
        if let startupError = dataStore.startupError {
            VStack(spacing: 16) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text("本机资料初始化失败")
                    .font(.headline)
                Text(startupError)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("重试") { dataStore.retryStartup() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
        } else if auth.isLoggedIn {

            VStack(spacing: 0) {
                if auth.isCloudAccount {
                    HStack(spacing: 8) {
                        Group {
                            switch cloudSyncStatus {
                            case .preparing:
                                Label("正在准备同步…", systemImage: "icloud.fill")
                            case .uploading:
                                Label("正在双向同步…", systemImage: "arrow.triangle.2.circlepath")
                            case .completed(let customers, let agencies, let trips):
                                Label("同步完成：客户 \(customers) 位、旅行社 \(agencies) 家、行程 \(trips) 条", systemImage: "icloud.fill")
                            case .failed:
                                Label("同步失败", systemImage: "exclamationmark.icloud.fill")
                            }
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if !isSyncing {
                            Button("重新同步") { Task { await syncLocalData() } }
                                .font(.caption.weight(.semibold))
                        }
                        if !pendingSyncConflicts.isEmpty {
                            Button("待处理冲突 \(pendingSyncConflicts.count)") { isShowingSyncConflicts = true }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.cyan.opacity(0.12))
                }
                ContentView()
            }

        } else {
            LoginView()
        }
        }
        .task(id: storeTaskIdentity) {
            guard dataStore.startupError == nil else { return }
            guard (dataStore.activeMode == .cloud) == auth.isCloudAccount else {
                dataStore.activate(forCloudAccount: auth.isCloudAccount)
                return
            }
            if auth.isCloudAccount {
                await prepareCloudSync()
            } else if auth.isLoggedIn {
                await prepareLocalDataScope()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && auth.isCloudAccount && hasCloudImportConsent && cloudImportCounts == nil {
                Task { await syncLocalData() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountAssetsDidChange)) { _ in
            guard auth.isCloudAccount, hasCloudImportConsent, cloudImportCounts == nil else { return }
            pendingAssetSyncTask?.cancel()
            pendingAssetSyncTask = Task {
                do {
                    try await Task.sleep(for: .milliseconds(900))
                } catch {
                    return
                }
                guard !Task.isCancelled, auth.isCloudAccount, cloudImportCounts == nil else { return }
                // Only the debounce timer is cancellable. Once the network sync
                // starts, later edits must not cancel its URLSession requests.
                pendingAssetSyncTask = nil
                guard !assetSyncInProgress else {
                    assetSyncNeedsAnotherPass = true
                    return
                }

                assetSyncInProgress = true
                repeat {
                    assetSyncNeedsAnotherPass = false
                    await syncAccountAssets()
                } while assetSyncNeedsAnotherPass && auth.isCloudAccount
                assetSyncInProgress = false
            }
        }
        .alert("同步失败", isPresented: Binding(
            get: { syncErrorMessage != nil },
            set: { if !$0 { syncErrorMessage = nil } }
        )) {
            Button("关闭", role: .cancel) { syncErrorMessage = nil }
        } message: {
            Text(syncErrorMessage ?? "")
        }
        .sheet(isPresented: $isShowingSyncConflicts) {
            SyncConflictResolutionView(conflicts: pendingSyncConflicts) {
                Task {
                    await refreshPendingSyncConflicts()
                    await syncLocalData()
                }
            }
        }
        .alert("同步本机资料到云端？", isPresented: Binding(
            get: { cloudImportCounts != nil },
            set: { if !$0 { cloudImportCounts = nil } }
        )) {
            Button("上传并同步") {
                do {
                    let localEmail = UserDefaults.standard.string(forKey: "auth.lastLocalEmail")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                    try dataStore.importLocalAccountToCloud(fromLocalEmail: localEmail, toCloudEmail: auth.currentEmail)
                    CloudLocalDataPreference.syncLocalData.save(for: auth.currentEmail)
                    UserDefaults.standard.set(true, forKey: cloudImportConsentKey)
                    cloudImportCounts = nil
                    Task { await syncLocalData() }
                } catch {
                    syncErrorMessage = error.localizedDescription
                }
            }
            Button("仅使用云端资料", role: .cancel) {
                CloudLocalDataPreference.cloudDataOnly.save(for: auth.currentEmail)
                UserDefaults.standard.set(true, forKey: cloudImportConsentKey)
                cloudImportCounts = nil
                Task { await syncLocalData() }
            }
        } message: {
            if let counts = cloudImportCounts {
                Text(String(format: String(localized: "本机发现客户 %d 位、旅行社 %d 家、行程 %d 条。请选择默认的数据使用方式。选择“上传并同步”会将本机资料导入云端；选择“仅使用云端资料”会保留本机资料在设备上，并继续使用云端已有资料。之后可在设置中修改。"), counts.customers, counts.agencies, counts.trips))
            }
        }
    }

    @MainActor
    private func prepareCloudSync() async {
        guard auth.isCloudAccount else { return }
        guard !auth.currentEmail.isEmpty else { return }
        pendingSyncConflicts = []

        let customers: Int
        let agencies: Int
        let trips: Int
        let deletions: Int
        let localEmail = UserDefaults.standard.string(forKey: "auth.lastLocalEmail")?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        AccountAssetStore.migrateLegacyAssetsToLocal(email: localEmail)
        let sourceScope = localEmail.isEmpty ? DataOwnership.legacyLocalScope : DataOwnership.localScope(email: localEmail)
        do {
            guard let localContainer = dataStore.localContainer else {
                throw LegacyStoreMigrator.MigrationError.storesUnavailable
            }
            let localContext = ModelContext(localContainer)
            customers = try localContext.fetch(FetchDescriptor<Custumer>()).filter { $0.ownerScope == sourceScope || $0.ownerScope == DataOwnership.legacyLocalScope }.count
            agencies = try localContext.fetch(FetchDescriptor<TravelAgency>()).filter { $0.ownerScope == sourceScope || $0.ownerScope == DataOwnership.legacyLocalScope }.count
            trips = try localContext.fetch(FetchDescriptor<TripBookingRecord>()).filter { $0.ownerScope == sourceScope || $0.ownerScope == DataOwnership.legacyLocalScope }.count
            deletions = try localContext.fetch(FetchDescriptor<CloudSyncDeletion>()).filter { $0.ownerScope == sourceScope || $0.ownerScope == DataOwnership.legacyLocalScope }.count
        } catch {
            cloudSyncStatus = .failed
            syncErrorMessage = error.localizedDescription
            return
        }
        let email = auth.currentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hasUnimportedAssets = DataOwnership.hasUnimportedLocalAssets(from: localEmail, to: email)

        if let preference = CloudLocalDataPreference.load(for: email) {
            UserDefaults.standard.set(true, forKey: cloudImportConsentKey)
            if preference == .syncLocalData {
                do {
                    try dataStore.importLocalAccountToCloud(fromLocalEmail: localEmail, toCloudEmail: email)
                } catch {
                    cloudSyncStatus = .failed
                    syncErrorMessage = error.localizedDescription
                    return
                }
            }
            await syncLocalData()
            return
        }

        guard customers + agencies + trips + deletions > 0 || hasUnimportedAssets else {
            UserDefaults.standard.set(true, forKey: cloudImportConsentKey)
            await syncLocalData()
            return
        }

        cloudImportCounts = CloudImportCounts(customers: customers, agencies: agencies, trips: trips)
    }

    @MainActor
    private func prepareLocalDataScope() async {
        let scope = DataOwnership.localScope(email: auth.currentEmail)
        AccountAssetStore.migrateLegacyAssetsToLocal(email: auth.currentEmail)
        DataOwnership.activateLocal(scope: scope)
        do {
            try DataOwnership.adoptLegacyLocalRecords(context: modelContext, scope: scope)
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func syncLocalData() async {
        guard auth.isCloudAccount, hasCloudImportConsent, cloudImportCounts == nil, !isSyncing else { return }
        isSyncing = true
        cloudSyncStatus = .uploading
        defer { isSyncing = false }
        do {
            guard let token = (await auth.refreshCloudAccessToken()) ?? auth.cloudAccessToken else {
                throw SupabaseDataSync.SyncError.noSession
            }
            let result = try await SupabaseDataSync.uploadLocalData(context: modelContext, accessToken: token)
            cloudSyncStatus = .completed(customers: result.customers, agencies: result.agencies, trips: result.trips)
            await refreshPendingSyncConflicts()
        } catch {
            cloudSyncStatus = .failed
            syncErrorMessage = error.localizedDescription
            await refreshPendingSyncConflicts()
        }
    }

    @MainActor
    private func refreshPendingSyncConflicts() async {
        let scope = DataOwnership.activeScope
        pendingSyncConflicts = (try? modelContext.fetch(FetchDescriptor<CloudSyncConflict>(predicate: #Predicate { $0.ownerScope == scope }))) ?? []
    }

    @MainActor
    private func syncAccountAssets() async {
        guard auth.isCloudAccount, hasCloudImportConsent, cloudImportCounts == nil else { return }
        do {
            guard let token = (await auth.refreshCloudAccessToken()) ?? auth.cloudAccessToken else {
                throw SupabaseDataSync.SyncError.noSession
            }
            try await SupabaseDataSync.syncAccountAssets(email: auth.currentEmail, accessToken: token)
        } catch {
            cloudSyncStatus = .failed
            syncErrorMessage = error.localizedDescription
        }
    }
}

private struct CloudImportCounts {
    let customers: Int
    let agencies: Int
    let trips: Int
}

private enum CloudSyncStatus {
    case preparing
    case uploading
    case completed(customers: Int, agencies: Int, trips: Int)
    case failed
}

private struct SyncConflictResolutionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State var conflicts: [CloudSyncConflict]
    let onResolved: () -> Void
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(conflicts, id: \.key) { conflict in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(title(for: conflict))
                            .font(.headline)
                        Text("本机\(conflict.isLocalDeletion ? "删除" : "修改")：\(conflict.localUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("云端\(conflict.isRemoteDeletion ? "删除" : "修改")：\(conflict.remoteUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(comparisonRows(for: conflict)) { field in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.label).font(.caption.weight(.semibold))
                                HStack(alignment: .top, spacing: 8) {
                                    Text("本机：\(field.local)")
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)
                                    Text("云端：\(field.remote)")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        Text("选择一侧后，该记录及关联内容会按所选版本继续同步。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button(localChoiceTitle(for: conflict)) { resolve(conflict, keepRemote: false) }
                                .buttonStyle(.bordered)
                            Button(remoteChoiceTitle(for: conflict)) { resolve(conflict, keepRemote: true) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("同步冲突")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("无法处理冲突", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("关闭", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func title(for conflict: CloudSyncConflict) -> String {
        guard let data = conflict.remotePayloadJSON.data(using: .utf8),
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "\(conflict.tableName) · \(conflict.recordID)"
        }
        let name = (row["name"] as? String) ?? (row["customer_name"] as? String) ?? (row["agency_code"] as? String)
        let kind: String
        switch conflict.tableName {
        case "customers": kind = "客户"
        case "travel_agencies": kind = "旅行社"
        case "trips": kind = "行程"
        default: kind = "记录"
        }
        return name.map { "\(kind)：\($0)" } ?? "\(kind)：\(conflict.recordID)"
    }

    private func resolve(_ conflict: CloudSyncConflict, keepRemote: Bool) {
        do {
            try SupabaseDataSync.resolveConflict(conflict, keepRemote: keepRemote, context: modelContext)
            conflicts.removeAll { $0.key == conflict.key }
            if conflicts.isEmpty {
                dismiss()
                onResolved()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func localChoiceTitle(for conflict: CloudSyncConflict) -> String {
        if conflict.isLocalDeletion { return "保留删除" }
        if conflict.isRemoteDeletion { return "恢复本机" }
        return "保留本机"
    }

    private func remoteChoiceTitle(for conflict: CloudSyncConflict) -> String {
        if conflict.isLocalDeletion { return "恢复云端" }
        if conflict.isRemoteDeletion { return "接受删除" }
        return "保留云端"
    }

    private func comparisonRows(for conflict: CloudSyncConflict) -> [ConflictField] {
        guard let data = conflict.remotePayloadJSON.data(using: .utf8),
              let remote = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let id = conflict.recordID
        let scope = conflict.ownerScope
        var fields: [(String, String, String)] = []
        switch conflict.tableName {
        case "customers":
            let local = try? modelContext.fetch(FetchDescriptor<Custumer>(predicate: #Predicate { $0.uuid == id && $0.ownerScope == scope })).first
            fields = [
                ("姓名", local?.name ?? "已删除", remote["name"] as? String ?? "—"),
                ("邮箱", local?.email ?? "已删除", remote["email"] as? String ?? "—"),
                ("备注", local?.remark ?? "已删除", remote["remark"] as? String ?? "—")
            ]
        case "travel_agencies":
            let local = try? modelContext.fetch(FetchDescriptor<TravelAgency>(predicate: #Predicate { $0.uuid == id && $0.ownerScope == scope })).first
            fields = [
                ("名称", local?.name ?? "已删除", remote["name"] as? String ?? "—"),
                ("旅行社代码", local?.agencyCode ?? "已删除", remote["agency_code"] as? String ?? "—"),
                ("联系人", local?.contactPerson ?? "已删除", remote["contact_person"] as? String ?? "—"),
                ("电话", local?.phone ?? "已删除", remote["phone"] as? String ?? "—")
            ]
        case "trips":
            let tripID = UUID(uuidString: id)
            let local = tripID.flatMap { uuid in
                try? modelContext.fetch(FetchDescriptor<TripBookingRecord>(predicate: #Predicate { $0.id == uuid && $0.ownerScope == scope })).first
            }
            fields = [
                ("客户", local?.customerName ?? "已删除", remote["customer_name"] as? String ?? "—"),
                ("服务类型", local?.serviceType ?? "已删除", remote["service_type"] as? String ?? "—"),
                ("起点", local?.locationStart ?? "已删除", remote["location_start"] as? String ?? "—"),
                ("目的地", local?.locationEnd ?? "已删除", remote["location_end"] as? String ?? "—"),
                ("航班号", local?.flightInfo ?? "已删除", remote["flight_info"] as? String ?? "—"),
                ("费用", local.map { String(format: "%.2f", $0.price) } ?? "已删除", remote["price"].map { String(describing: $0) } ?? "—")
            ]
        default:
            break
        }
        if conflict.isRemoteDeletion {
            fields = fields.map { ($0.0, $0.1, "已删除") }
        }
        return fields.map { ConflictField(label: $0.0, local: $0.1, remote: $0.2) }
    }
}

private struct ConflictField: Identifiable {
    let label: String
    let local: String
    let remote: String
    var id: String { label }
}


//
//#Preview {
//    @Previewable @State var dataSource = DataSource()
//
//        RootView()
//        .environment(dataSource)
//}
