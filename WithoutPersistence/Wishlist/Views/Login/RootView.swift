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
    @Environment(AppLanguageSettings.self) private var languageSettings
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppDataContainerManager.self) private var dataStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var cloudSyncStatus: CloudSyncStatus = .preparing
    @State private var isSyncing = false
    @State private var syncErrorMessage: String?
    @State private var pendingAssetSyncTask: Task<Void, Never>?
    @State private var syncRetryTask: Task<Void, Never>?
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

    private var accountTaskIdentity: String {
        [auth.isLoggedIn.description, auth.isCloudAccount.description, auth.currentEmail].joined(separator: "|")
    }

    private var storeTaskIdentity: String {
        [accountTaskIdentity, auth.productEdition.rawValue, dataStore.activeMode.rawValue,
         dataStore.startupError ?? ""].joined(separator: "|")
    }

    private func syncStatusText(completed: (Int, Int, Int)?, failed: Bool) -> String {
        switch languageSettings.selectedLanguage {
        case .simplifiedChinese:
            if failed { return "同步失败" }
            guard let completed else { return isSyncing ? "正在双向同步…" : "正在准备同步…" }
            return "同步完成：客户 \(completed.0) 位、旅行社 \(completed.1) 家、行程 \(completed.2) 条"
        case .traditionalChinese:
            if failed { return "同步失敗" }
            guard let completed else { return isSyncing ? "正在雙向同步…" : "正在準備同步…" }
            return "同步完成：客戶 \(completed.0) 位、旅行社 \(completed.1) 家、行程 \(completed.2) 筆"
        case .english:
            if failed { return "Sync failed" }
            guard let completed else { return isSyncing ? "Syncing changes both ways…" : "Preparing to sync…" }
            return "Sync complete: \(completed.0) customers, \(completed.1) agencies, \(completed.2) trips"
        case .spanish:
            if failed { return "Sincronización fallida" }
            guard let completed else { return isSyncing ? "Sincronizando en ambas direcciones…" : "Preparando la sincronización…" }
            return "Sincronización completa: \(completed.0) clientes, \(completed.1) agencias y \(completed.2) viajes"
        case .japanese:
            if failed { return "同期に失敗しました" }
            guard let completed else { return isSyncing ? "双方向で同期中…" : "同期の準備中…" }
            return "同期完了：顧客 \(completed.0) 人、旅行会社 \(completed.1) 社、旅行 \(completed.2) 件"
        case .korean:
            if failed { return "동기화 실패" }
            guard let completed else { return isSyncing ? "양방향 동기화 중…" : "동기화 준비 중…" }
            return "동기화 완료: 고객 \(completed.0)명, 여행사 \(completed.1)곳, 일정 \(completed.2)건"
        }
    }

    private var syncButtonTitle: String {
        switch languageSettings.selectedLanguage {
        case .simplifiedChinese: "重新同步"
        case .traditionalChinese: "重新同步"
        case .english: "Sync again"
        case .spanish: "Sincronizar de nuevo"
        case .japanese: "再同期"
        case .korean: "다시 동기화"
        }
    }

    private var cloudDataStatusTitle: String {
        switch languageSettings.selectedLanguage {
        case .simplifiedChinese: "云端资料实时读取"
        case .traditionalChinese: "即時讀取雲端資料"
        case .english: "Cloud data is loaded directly"
        case .spanish: "Los datos se leen directamente de la nube"
        case .japanese: "クラウドデータを直接読み込みます"
        case .korean: "클라우드 데이터를 직접 불러옵니다"
        }
    }

    private var pendingConflictsTitle: String {
        let count = pendingSyncConflicts.count
        return switch languageSettings.selectedLanguage {
        case .simplifiedChinese: "待处理冲突 \(count)"
        case .traditionalChinese: "待處理衝突 \(count)"
        case .english: "Pending conflicts \(count)"
        case .spanish: "Conflictos pendientes \(count)"
        case .japanese: "未解決の競合 \(count)"
        case .korean: "대기 중인 충돌 \(count)"
        }
    }

    private var entitlementStatusCopy: (title: String, message: String, retry: String, signOut: String) {
        let language = languageSettings.selectedLanguage
        let isOnlineOnly = auth.serverEntitlement?.edition == .cloud && auth.serverEntitlement?.isCurrentlyActive == true
        if auth.deviceLimitReached {
            switch language {
            case .simplifiedChinese: return ("设备数量已达上限", "此账号已达到可用设备数。请先在另一台设备退出账号，再重试；也可以联系管理员增加设备额度。", "重新检查", "退出登录")
            case .traditionalChinese: return ("裝置數量已達上限", "此帳號已達可用裝置數。請先在另一台裝置登出，再重試；也可以聯絡管理員增加裝置額度。", "重新檢查", "登出")
            case .english: return ("Device limit reached", "This account has used all available devices. Sign out on another device and try again, or contact the administrator to increase the limit.", "Check again", "Sign out")
            case .spanish: return ("Límite de dispositivos alcanzado", "Esta cuenta ya usa todos sus dispositivos disponibles. Cierra sesión en otro dispositivo e inténtalo de nuevo, o contacta con el administrador para ampliar el límite.", "Comprobar", "Cerrar sesión")
            case .japanese: return ("登録できる端末数の上限です", "このアカウントで利用できる端末数に達しました。別の端末でログアウトして再試行するか、管理者に上限の変更を依頼してください。", "再確認", "ログアウト")
            case .korean: return ("기기 수 한도에 도달했습니다", "이 계정의 사용 가능한 기기 수를 모두 사용했습니다. 다른 기기에서 로그아웃한 뒤 다시 시도하거나 관리자에게 한도 변경을 요청하세요.", "다시 확인", "로그아웃")
            }
        }
        if auth.entitlementLookupFailed {
            if auth.requiresCloudReauthentication {
                switch language {
                case .simplifiedChinese: return ("登录状态已失效", "云端账号需要重新登录才能继续。账号资料仍保存在云端，本机资料未被删除。", "退出并重新登录", "退出登录")
                case .traditionalChinese: return ("登入狀態已失效", "雲端帳號需要重新登入才能繼續。帳號資料仍保存在雲端，本機資料未被刪除。", "登出並重新登入", "登出")
                case .english: return ("Sign-in expired", "Sign in again to continue using cloud data. Your account data remains in the cloud, and local data hasn’t been deleted.", "Sign out and sign in again", "Sign out")
                case .spanish: return ("La sesión ha caducado", "Vuelve a iniciar sesión para usar los datos de la nube. Tus datos siguen allí y los datos locales no se han eliminado.", "Cerrar sesión y volver a entrar", "Cerrar sesión")
                case .japanese: return ("ログインの有効期限が切れました", "クラウドデータを引き続き使うには、もう一度ログインしてください。アカウントデータはクラウドにあり、ローカルデータも削除されていません。", "ログアウトして再ログイン", "ログアウト")
                case .korean: return ("로그인 세션이 만료되었습니다", "클라우드 데이터를 계속 사용하려면 다시 로그인하세요. 계정 데이터는 클라우드에 있으며 로컬 데이터도 삭제되지 않았습니다.", "로그아웃 후 다시 로그인", "로그아웃")
                }
            }
            switch language {
            case .simplifiedChinese: return ("无法验证云端权限", "请检查网络后重试。当前账号资料未被删除。", "重试", "退出登录")
            case .traditionalChinese: return ("無法驗證雲端權限", "請檢查網路後重試。此帳號資料未被刪除。", "重試", "登出")
            case .english: return ("Can’t verify cloud access", "Check your internet connection and try again. Your account data hasn’t been deleted.", "Retry", "Sign out")
            case .spanish: return ("No se puede verificar el acceso a la nube", "Comprueba la conexión e inténtalo de nuevo. No se han eliminado tus datos.", "Reintentar", "Cerrar sesión")
            case .japanese: return ("クラウドアクセスを確認できません", "ネットワークを確認して再試行してください。アカウントのデータは削除されていません。", "再試行", "ログアウト")
            case .korean: return ("클라우드 액세스를 확인할 수 없습니다", "인터넷 연결을 확인한 후 다시 시도하세요. 계정 데이터는 삭제되지 않았습니다.", "다시 시도", "로그아웃")
            }
        }
        if isOnlineOnly {
            switch language {
            case .simplifiedChinese: return ("在线专用版", "此账号直接使用云端资料，请确认网络连接并重新验证权限。账号资料仍保存在云端。", "重新检查", "退出登录")
            case .traditionalChinese: return ("線上專用版", "此帳號直接使用雲端資料，請確認網路連線並重新驗證權限。帳號資料仍保存在雲端。", "重新檢查", "登出")
            case .english: return ("Online-only edition", "This account uses cloud data directly. Check your connection and verify access again. Your account data remains in the cloud.", "Check again", "Sign out")
            case .spanish: return ("Edición solo en línea", "Esta cuenta usa directamente los datos de la nube. Comprueba la conexión y vuelve a verificar el acceso. Tus datos siguen en la nube.", "Comprobar", "Cerrar sesión")
            case .japanese: return ("オンライン専用版", "このアカウントはクラウドデータを直接使用します。ネットワークを確認し、アクセスを再確認してください。データはクラウドに保存されています。", "再確認", "ログアウト")
            case .korean: return ("온라인 전용 버전", "이 계정은 클라우드 데이터를 직접 사용합니다. 네트워크를 확인하고 액세스를 다시 확인하세요. 계정 데이터는 클라우드에 있습니다.", "다시 확인", "로그아웃")
            }
        }
        switch language {
        case .simplifiedChinese: return ("云端权限未开通", "此账号没有有效的云端使用权限。资料没有删除，请联系管理员开通。", "重新检查", "退出登录")
        case .traditionalChinese: return ("尚未開通雲端權限", "此帳號沒有有效的雲端使用權限。資料未遭刪除，請聯絡管理員開通。", "重新檢查", "登出")
        case .english: return ("Cloud access isn’t active", "This account has no active cloud entitlement. Your data hasn’t been deleted. Contact the administrator to enable access.", "Check again", "Sign out")
        case .spanish: return ("El acceso a la nube no está activo", "Esta cuenta no tiene acceso activo. Tus datos no se han eliminado. Contacta con el administrador para activarlo.", "Comprobar", "Cerrar sesión")
        case .japanese: return ("クラウド権限が有効ではありません", "このアカウントには有効なクラウド権限がありません。データは削除されていません。管理者にお問い合わせください。", "再確認", "ログアウト")
        case .korean: return ("클라우드 권한이 활성화되지 않았습니다", "이 계정에는 활성화된 클라우드 권한이 없습니다. 데이터는 삭제되지 않았습니다. 관리자에게 문의하세요.", "다시 확인", "로그아웃")
        }
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
        } else if auth.isCloudAccount && !auth.entitlementLookupCompleted {
            VStack(spacing: 14) {
                ProgressView()
                Text(entitlementCheckingTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if auth.shouldBlockCloudClient {
            VStack(spacing: 16) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                Text(entitlementStatusCopy.title)
                    .font(.headline)
                Text(entitlementStatusCopy.message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button(entitlementStatusCopy.retry) {
                    if auth.requiresCloudReauthentication {
                        auth.logout()
                    } else {
                        Task { await auth.retryServerEntitlementLookup() }
                    }
                }
                .buttonStyle(.borderedProminent)
                if !auth.requiresCloudReauthentication {
                    Button(entitlementStatusCopy.signOut) { auth.logout() }
                        .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if auth.isLoggedIn {

            VStack(spacing: 0) {
                if auth.productEdition.allowsCrossDeviceSync {
                    HStack(spacing: 8) {
                        Group {
                            switch cloudSyncStatus {
                            case .preparing:
                                Label(syncStatusText(completed: nil, failed: false), systemImage: "icloud.fill")
                            case .uploading:
                                Label(syncStatusText(completed: nil, failed: false), systemImage: "arrow.triangle.2.circlepath")
                            case .completed(let customers, let agencies, let trips):
                                let message = syncStatusText(completed: (customers, agencies, trips), failed: false)
                                Label(message, systemImage: "icloud.fill")
                            case .failed:
                                Label(syncStatusText(completed: nil, failed: true), systemImage: "exclamationmark.icloud.fill")
                            }
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if !isSyncing {
                            Button(syncButtonTitle) { Task { await syncLocalData(force: true) } }
                                .font(.caption.weight(.semibold))
                        }
                        if !pendingSyncConflicts.isEmpty {
                            Button(pendingConflictsTitle) { isShowingSyncConflicts = true }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color.cyan.opacity(0.12))
                }
                // SwiftData @Query predicates capture the active account scope
                // when ContentView is initialized. Recreate the view tree when
                // the signed-in account, storage mode, or language changes so
                // cached navigation labels and queries refresh together.
                ContentView()
                    .id("\(storeTaskIdentity)|\(languageSettings.identifier)")
            }

        } else {
            LoginView()
        }
        }
        .environment(\.locale, languageSettings.locale)
        // Entitlement verification is an account-scoped network operation.
        // Do not key it to productEdition or storage mode: both can change
        // while startup is in progress and would cancel the request.
        .task(id: accountTaskIdentity) {
            syncRetryTask?.cancel()
            guard dataStore.startupError == nil else { return }
            if (dataStore.activeMode == .cloud) != auth.isCloudAccount {
                dataStore.activate(forCloudAccount: auth.isCloudAccount)
            }
            if auth.isCloudAccount {
                await prepareCloudSync()
            } else if auth.isLoggedIn {
                await prepareLocalDataScope()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && auth.isCloudAccount && auth.serverEntitlement?.edition == .cloud && auth.entitlementLookupCompleted {
                Task { await auth.recheckOnlineOnlyAccessOnForeground() }
            } else if phase == .active && auth.canUseCurrentCloudEdition && auth.productEdition.allowsCrossDeviceSync && hasCloudImportConsent && cloudImportCounts == nil {
                Task { await syncLocalData() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountAssetsDidChange)) { _ in
            guard auth.canUseCurrentCloudEdition, auth.productEdition.allowsCrossDeviceSync, hasCloudImportConsent, cloudImportCounts == nil else { return }
            pendingAssetSyncTask?.cancel()
            pendingAssetSyncTask = Task {
                do {
                    try await Task.sleep(for: .milliseconds(900))
                } catch {
                    return
                }
                guard !Task.isCancelled, auth.canUseCurrentCloudEdition, auth.productEdition.allowsCrossDeviceSync, cloudImportCounts == nil else { return }
                // Only the debounce timer is cancellable. Once the network sync
                // starts, later edits must not cancel its URLSession requests.
                pendingAssetSyncTask = nil
                guard !assetSyncInProgress else {
                    assetSyncNeedsAnotherPass = true
                    return
                }

                assetSyncInProgress = true
                auth.setCloudSyncInProgress(true)
                repeat {
                    assetSyncNeedsAnotherPass = false
                    await syncAccountAssets()
                } while assetSyncNeedsAnotherPass && auth.canUseCurrentCloudEdition && auth.productEdition.allowsCrossDeviceSync
                assetSyncInProgress = false
                auth.setCloudSyncInProgress(isSyncing)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountScopedLocalDataDidClear)) { notification in
            guard let clearedScope = notification.object as? String,
                  clearedScope == DataOwnership.activeScope else { return }
            pendingAssetSyncTask?.cancel()
            pendingAssetSyncTask = nil
            assetSyncNeedsAnotherPass = false
            pendingSyncConflicts = []
            cloudSyncStatus = .completed(customers: 0, agencies: 0, trips: 0)
            clearScheduledSyncRetry()
        }
        .alert("同步失败", isPresented: Binding(
            get: { syncErrorMessage != nil },
            set: { if !$0 { syncErrorMessage = nil } }
        )) {
            Button("关闭", role: .cancel) { syncErrorMessage = nil }
        } message: {
            Text(syncErrorMessage ?? "")
        }
        .adaptiveFormPresentation(isPresented: $isShowingSyncConflicts) {
            SyncConflictResolutionView(conflicts: pendingSyncConflicts) {
                Task {
                    await refreshPendingSyncConflicts()
                    await syncLocalData(force: true)
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
                    Task { await syncLocalData(force: true) }
                } catch {
                    syncErrorMessage = error.localizedDescription
                }
            }
            Button("仅使用云端资料", role: .cancel) {
                CloudLocalDataPreference.cloudDataOnly.save(for: auth.currentEmail)
                UserDefaults.standard.set(true, forKey: cloudImportConsentKey)
                cloudImportCounts = nil
                Task { await syncLocalData(force: true) }
            }
        } message: {
            if let counts = cloudImportCounts {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本机资料包含：")
                    Text(String(format: String(localized: "客户 %1$d 位、旅行社 %2$d 家、行程 %3$d 条"), counts.customers, counts.agencies, counts.trips))
                    Text("请选择默认的数据使用方式。")
                    Text("选择“上传并同步”会将本机资料导入云端。")
                    Text("选择“仅使用云端资料”会保留本机资料，并继续使用云端已有资料。")
                    Text("之后可以在设置中修改。")
                }
            }
        }
    }

    private var entitlementCheckingTitle: String {
        switch languageSettings.selectedLanguage {
        case .simplifiedChinese: "正在验证云端权限…"
        case .traditionalChinese: "正在驗證雲端權限…"
        case .english: "Checking cloud access…"
        case .spanish: "Verificando el acceso a la nube…"
        case .japanese: "クラウドアクセスを確認中…"
        case .korean: "클라우드 액세스 확인 중…"
        }
    }

    @MainActor
    private func prepareCloudSync() async {
        guard auth.isCloudAccount else { return }
        guard !auth.currentEmail.isEmpty else { return }
        await auth.loadServerEntitlementIfNeeded()
        guard auth.isCloudAccount, auth.canUseCurrentCloudEdition else { return }
        pendingSyncConflicts = []

        // The online-only edition reads and writes directly through the
        // account-bound cloud views. Never import the device's SwiftData cache
        // or start the offline sync coordinator for this edition.
        if auth.productEdition == .cloud {
            DataOwnership.activateCloud(email: auth.currentEmail)
            CloudLocalDataPreference.cloudDataOnly.save(for: auth.currentEmail)
            UserDefaults.standard.set(true, forKey: cloudImportConsentKey)
            return
        }

        let email = auth.currentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lastCloudAccountKey = "auth.cloud.lastAccountOnDevice.v1"
        let previousCloudEmail = UserDefaults.standard.string(forKey: lastCloudAccountKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let switchedCloudAccounts = !previousCloudEmail.isEmpty && previousCloudEmail != email
        let localEmail = UserDefaults.standard.string(forKey: "auth.lastLocalEmail")?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let localAccountDoesNotMatchCloudAccount = !localEmail.isEmpty && localEmail != email
        let anotherCloudAccountHasDeviceData = hasCachedCloudDataForAnotherAccount(excluding: email)
        UserDefaults.standard.set(email, forKey: lastCloudAccountKey)

        // A cloud account switch starts from that account's own cloud data. The
        // device's local workspace may belong to the previous account, so never
        // import it automatically into a different cloud account.
        if switchedCloudAccounts || localAccountDoesNotMatchCloudAccount || anotherCloudAccountHasDeviceData {
            CloudLocalDataPreference.cloudDataOnly.save(for: email)
            UserDefaults.standard.set(true, forKey: cloudImportConsentKey)
            await syncLocalData()
            return
        }

        let customers: Int
        let agencies: Int
        let trips: Int
        let deletions: Int
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

    private func hasCachedCloudDataForAnotherAccount(excluding email: String) -> Bool {
        let currentScope = DataOwnership.cloudScope(for: email)
        if let cloudContainer = dataStore.cloudContainer {
            do {
                let context = ModelContext(cloudContainer)
                let customerScopes = try context.fetch(FetchDescriptor<Custumer>()).map(\.ownerScope)
                let agencyScopes = try context.fetch(FetchDescriptor<TravelAgency>()).map(\.ownerScope)
                let tripScopes = try context.fetch(FetchDescriptor<TripBookingRecord>()).map(\.ownerScope)
                let deletionScopes = try context.fetch(FetchDescriptor<CloudSyncDeletion>()).map(\.ownerScope)
                let conflictScopes = try context.fetch(FetchDescriptor<CloudSyncConflict>()).map(\.ownerScope)
                if (customerScopes + agencyScopes + tripScopes + deletionScopes + conflictScopes)
                    .contains(where: { $0.hasPrefix("cloud:") && $0 != currentScope }) {
                    return true
                }
            } catch {
                // If ownership cannot be checked, preserve account separation
                // by choosing cloud-only instead of importing local records.
                return true
            }
        }

        let assetPrefix = "accountAssets.cloud.v2."
        return UserDefaults.standard.dictionaryRepresentation().contains { key, value in
            key.hasPrefix(assetPrefix)
                && !key.hasSuffix(".updatedAt")
                && !key.hasPrefix("\(assetPrefix)\(email).")
                && value is Data
        }
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
    private func syncLocalData(force: Bool = false, showsError: Bool = true) async {
        guard auth.canUseCurrentCloudEdition, auth.productEdition.allowsCrossDeviceSync, hasCloudImportConsent, cloudImportCounts == nil, !isSyncing else { return }
        if !force, let retryDate = scheduledSyncRetryDate(), retryDate > .now {
            cloudSyncStatus = .failed
            scheduleSyncRetry(at: retryDate)
            return
        }
        syncRetryTask?.cancel()
        isSyncing = true
        auth.setCloudSyncInProgress(true)
        cloudSyncStatus = .uploading
        defer {
            isSyncing = false
            auth.setCloudSyncInProgress(assetSyncInProgress)
        }
        do {
            let syncEmail = auth.currentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let token = (await auth.refreshCloudAccessToken()) ?? auth.cloudAccessToken else {
                throw SupabaseDataSync.SyncError.noSession
            }
            guard auth.canUseCurrentCloudEdition, auth.productEdition.allowsCrossDeviceSync,
                  auth.currentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == syncEmail else {
                return
            }
            let result = try await SupabaseDataSync.uploadLocalData(
                context: modelContext,
                accessToken: token,
                accountEmail: syncEmail
            )
            clearScheduledSyncRetry()
            cloudSyncStatus = .completed(customers: result.customers, agencies: result.agencies, trips: result.trips)
            await refreshPendingSyncConflicts()
        } catch {
            cloudSyncStatus = .failed
            persistFailedSyncAndScheduleRetry()
            if showsError { syncErrorMessage = error.localizedDescription }
            await refreshPendingSyncConflicts()
        }
    }

    private var syncRetryStorageKey: String {
        "cloud.sync.retry.v1.\(auth.currentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func scheduledSyncRetryDate() -> Date? {
        UserDefaults.standard.object(forKey: "\(syncRetryStorageKey).nextAttemptAt") as? Date
    }

    @MainActor
    private func persistFailedSyncAndScheduleRetry() {
        let defaults = UserDefaults.standard
        let attemptsKey = "\(syncRetryStorageKey).failureCount"
        let attempts = min(defaults.integer(forKey: attemptsKey) + 1, 6)
        let delays: [TimeInterval] = [30, 60, 120, 300, 600, 900]
        let retryDate = Date().addingTimeInterval(delays[attempts - 1])
        defaults.set(attempts, forKey: attemptsKey)
        defaults.set(retryDate, forKey: "\(syncRetryStorageKey).nextAttemptAt")
        scheduleSyncRetry(at: retryDate)
    }

    @MainActor
    private func clearScheduledSyncRetry() {
        UserDefaults.standard.removeObject(forKey: "\(syncRetryStorageKey).failureCount")
        UserDefaults.standard.removeObject(forKey: "\(syncRetryStorageKey).nextAttemptAt")
        syncRetryTask?.cancel()
        syncRetryTask = nil
    }

    @MainActor
    private func scheduleSyncRetry(at date: Date) {
        syncRetryTask?.cancel()
        guard auth.canUseCurrentCloudEdition, auth.productEdition.allowsCrossDeviceSync, hasCloudImportConsent else { return }
        syncRetryTask = Task {
            let delay = max(0, date.timeIntervalSinceNow)
            let nanoseconds = UInt64(min(delay, 900) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, scenePhase == .active else { return }
            await syncLocalData(showsError: false)
        }
    }

    @MainActor
    private func refreshPendingSyncConflicts() async {
        let scope = DataOwnership.activeScope
        pendingSyncConflicts = (try? modelContext.fetch(FetchDescriptor<CloudSyncConflict>(predicate: #Predicate { $0.ownerScope == scope }))) ?? []
    }

    @MainActor
    private func syncAccountAssets() async {
        guard auth.canUseCurrentCloudEdition, auth.productEdition.allowsCrossDeviceSync, hasCloudImportConsent, cloudImportCounts == nil else { return }
        do {
            let syncEmail = auth.currentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let token = (await auth.refreshCloudAccessToken()) ?? auth.cloudAccessToken else {
                throw SupabaseDataSync.SyncError.noSession
            }
            guard auth.canUseCurrentCloudEdition, auth.productEdition.allowsCrossDeviceSync,
                  auth.currentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == syncEmail else {
                return
            }
            try await SupabaseDataSync.syncAccountAssets(email: syncEmail, accessToken: token)
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
                        title(for: conflict)
                            .font(.headline)
                        HStack(spacing: 4) {
                            Text(conflict.isLocalDeletion ? "本机删除" : "本机修改")
                            Text("：")
                            Text(conflict.localUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text(conflict.isRemoteDeletion ? "云端删除" : "云端修改")
                            Text("：")
                            Text(conflict.remoteUpdatedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        ForEach(comparisonRows(for: conflict)) { field in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(LocalizedStringKey(field.label)).font(.caption.weight(.semibold))
                                HStack(alignment: .top, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("本机")
                                        Text(field.local)
                                    }
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("云端")
                                        Text(field.remote)
                                    }
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

    private func title(for conflict: CloudSyncConflict) -> some View {
        guard let data = conflict.remotePayloadJSON.data(using: .utf8),
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return HStack(spacing: 0) {
                Text("记录")
                Text(" · ")
                Text(conflict.recordID)
            }
        }
        let name = (row["name"] as? String) ?? (row["customer_name"] as? String) ?? (row["agency_code"] as? String)
        let kind: LocalizedStringKey
        switch conflict.tableName {
        case "customers": kind = "客户"
        case "travel_agencies": kind = "旅行社"
        case "trips": kind = "行程"
        default: kind = "记录"
        }
        return HStack(spacing: 0) {
            Text(kind)
            Text("：")
            Text(name ?? conflict.recordID)
        }
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

    private func localChoiceTitle(for conflict: CloudSyncConflict) -> LocalizedStringKey {
        if conflict.isLocalDeletion { return "保留删除" }
        if conflict.isRemoteDeletion { return "恢复本机" }
        return "保留本机"
    }

    private func remoteChoiceTitle(for conflict: CloudSyncConflict) -> LocalizedStringKey {
        if conflict.isLocalDeletion { return "恢复云端" }
        if conflict.isRemoteDeletion { return "接受删除" }
        return "保留云端"
    }

    private func comparisonRows(for conflict: CloudSyncConflict) -> [ConflictField] {
        guard let data = conflict.remotePayloadJSON.data(using: .utf8),
              let remote = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let id = conflict.recordID
        let scope = conflict.ownerScope
        let deleted = String(localized: "已删除")
        var fields: [(String, String, String)] = []
        switch conflict.tableName {
        case "customers":
            let local = try? modelContext.fetch(FetchDescriptor<Custumer>(predicate: #Predicate { $0.uuid == id && $0.ownerScope == scope })).first
            fields = [
                ("姓名", local?.name ?? deleted, remote["name"] as? String ?? "—"),
                ("邮箱", local?.email ?? deleted, remote["email"] as? String ?? "—"),
                ("备注", local?.remark ?? deleted, remote["remark"] as? String ?? "—")
            ]
        case "travel_agencies":
            let local = try? modelContext.fetch(FetchDescriptor<TravelAgency>(predicate: #Predicate { $0.uuid == id && $0.ownerScope == scope })).first
            fields = [
                ("名称", local?.name ?? deleted, remote["name"] as? String ?? "—"),
                ("旅行社代码", local?.agencyCode ?? deleted, remote["agency_code"] as? String ?? "—"),
                ("联系人", local?.contactPerson ?? deleted, remote["contact_person"] as? String ?? "—"),
                ("电话", local?.phone ?? deleted, remote["phone"] as? String ?? "—")
            ]
        case "trips":
            let tripID = UUID(uuidString: id)
            let local = tripID.flatMap { uuid in
                try? modelContext.fetch(FetchDescriptor<TripBookingRecord>(predicate: #Predicate { $0.id == uuid && $0.ownerScope == scope })).first
            }
            fields = [
                ("客户", local?.customerName ?? deleted, remote["customer_name"] as? String ?? "—"),
                ("服务类型", local?.serviceType ?? deleted, remote["service_type"] as? String ?? "—"),
                ("起点", local?.locationStart ?? deleted, remote["location_start"] as? String ?? "—"),
                ("目的地", local?.locationEnd ?? deleted, remote["location_end"] as? String ?? "—"),
                ("航班号", local?.flightInfo ?? deleted, remote["flight_info"] as? String ?? "—"),
                ("费用", local.map { String(format: "%.2f", $0.price) } ?? deleted, remote["price"].map { String(describing: $0) } ?? "—")
            ]
        default:
            break
        }
        if conflict.isRemoteDeletion {
            fields = fields.map { ($0.0, $0.1, deleted) }
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
