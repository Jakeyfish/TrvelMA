import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import StoreKit

extension Notification.Name {
    static let recheckLocalAccess = Notification.Name("TrvelMA.recheckLocalAccess")
}

/// Mounted only when local enforcement is enabled; cloud authorization remains separate.
struct LocalAccountWorkspace: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppDataContainerManager.self) private var dataStore
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = StorePurchaseManager()
    @State private var access: LegacyLocalAccessPolicy.WorkspaceAccess?
    @State private var preparedEmail: String?
    @State private var busy = false
    @State private var refreshAgain = false
    @State private var error = ""

    var body: some View {
        Group {
            if access?.allowsEditing == true, preparedEmail == auth.currentEmail {
                ContentView().disabled(busy)
                    .overlay(alignment: .top) { if busy { ProgressView().padding() } }
            } else if let access, preparedEmail == auth.currentEmail {
                LocalAccountArchiveView(needsPurchase: access.allowsPurchase, busy: busy,
                                        error: error, retry: { Task { await refresh() } },
                                        restore: { Task { await restore() } })
            } else {
                VStack(spacing: 16) {
                    if busy { ProgressView() }
                    Text("正在验证本地使用权限…")
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                    Button("重试") { Task { await refresh() } }.disabled(busy)
                    Button("退出登录") { auth.logout() }.disabled(busy)
                }.padding()
            }
        }
        .task(id: auth.currentEmail) { await refresh() }
        .task {
            // A pending buyout or refund can arrive while the app stays foregrounded.
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                guard case .verified(let transaction) = result, transaction.productID == StoreProductCatalog.local else { continue }
                await refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .recheckLocalAccess)) { _ in
            Task { await refresh() }
        }
    }

    @MainActor private func refresh() async {
        guard !busy else { refreshAgain = true; return }
        guard auth.isLoggedIn, !auth.isCloudAccount, dataStore.activeMode == .local else { return }
        let email = auth.currentEmail
        busy = true; refreshAgain = false; error = ""
        defer {
            busy = false
            if refreshAgain {
                refreshAgain = false
                Task { await refresh() }
            }
        }
        do {
            if preparedEmail != email {
                AccountAssetStore.migrateLegacyAssetsToLocal(email: email)
                let scope = DataOwnership.localScope(email: email)
                DataOwnership.activateLocal(scope: scope)
                try DataOwnership.adoptLegacyLocalRecords(context: context, scope: scope)
            }
            await store.refreshLocalAccessEvidence()
            guard !Task.isCancelled, auth.isLoggedIn, !auth.isCloudAccount,
                  auth.currentEmail == email, dataStore.activeMode == .local else { return }
            preparedEmail = email
            access = store.localWorkspaceAccess
        } catch {
            guard auth.currentEmail == email, !Task.isCancelled else { return }
            access = nil
            self.error = error.localizedDescription
        }
    }

    @MainActor private func restore() async {
        guard !busy else { return }
        busy = true
        let email = auth.currentEmail
        await store.restore()
        busy = false
        guard auth.currentEmail == email, !auth.isCloudAccount, auth.isLoggedIn else { return }
        await refresh()
        error = store.message
    }
}

private struct LocalAccountArchiveView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var context
    let needsPurchase: Bool
    let busy: Bool
    let error: String
    let retry: () -> Void
    let restore: () -> Void
    @State private var snapshot: [String: Any] = [:]
    @State private var exportData = Data()
    @State private var exportError = ""
    @State private var exporting = false
    private let sections = [("trips", "行程"), ("customers", "客户"), ("travel_agencies", "旅行社")]
    private let fields = [("appointment_date", "接载日期"), ("appointment_time", "接载时间"),
        ("customer_contact", "联系方式"), ("email", "邮箱"), ("phone", "电话"),
        ("location_start", "起始点"), ("location_end", "目的地"), ("price", "金额"), ("tip", "小费"),
        ("flight_info", "航班"), ("memo", "备注"), ("travel_agency_name", "旅行社"),
        ("travel_agency_order_number", "旅行社订单号")]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(needsPurchase ? "本地使用权限尚未开通，可恢复购买或查看版本。" : "暂时无法确认本地使用权限，请重试或恢复购买。")
                    Text("已有资料仍可查看和导出。新增、编辑、结算、航班刷新和同步已暂停。")
                    Text("导出文件包含个人及业务资料，请妥善保管。").font(.footnote).foregroundStyle(.secondary)
                    Text("导出包含业务记录和本地名片资料，不包含登录凭据或远程图片原文件。").font(.footnote).foregroundStyle(.secondary)
                    if busy { ProgressView() }
                    if !error.isEmpty { Text(error).foregroundStyle(.secondary) }
                    if !exportError.isEmpty { Text(exportError).foregroundStyle(.red) }
                    Button("导出全部资料") { exporting = true }.disabled(exportData.isEmpty || busy)
                    Button("重新加载资料") { load() }.disabled(busy)
                    Button("重新检查授权", action: retry).disabled(busy)
                    Button("恢复购买", action: restore).disabled(busy)
                    if needsPurchase && BillingReleaseConfiguration.plansVisible {
                        Button("版本与购买") { NotificationCenter.default.post(name: .requestPurchasePlans, object: nil) }.disabled(busy)
                    }
                    Button("退出登录") { auth.logout() }.disabled(busy)
                }
                ForEach(sections, id: \.0) { section in
                    let rows = snapshot[section.0] as? [[String: Any]] ?? []
                    Section("\(AppLocalization.text(section.1)) · \(rows.count)") {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            DisclosureGroup((row["customer_name"] ?? row["name"]) as? String ?? AppLocalization.text(section.1)) {
                                ForEach(fields, id: \.0) { field in
                                    if let value = row[field.0], !(value is NSNull), !String(describing: value).isEmpty {
                                        LabeledContent(AppLocalization.text(field.1), value: String(describing: value)).textSelection(.enabled)
                                    }
                                }
                                Text("完整资料包含在导出文件中。").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("本地资料 · 只读")
            .task(id: auth.currentEmail) { load() }
            .fileExporter(isPresented: $exporting, document: AccountArchiveDocument(data: exportData), contentType: .json,
                          defaultFilename: AppLocalization.text("TrvelMA-资料备份")) { result in
                if case .failure(let failure) = result { exportError = failure.localizedDescription }
            }
        }
    }

    @MainActor private func load() {
        snapshot = [:]; exportData = Data(); exportError = ""
        guard auth.isLoggedIn, !auth.isCloudAccount else { return }
        do {
            let next = try LocalAccountArchive.snapshot(context: context, email: auth.currentEmail)
            let data = try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .sortedKeys])
            snapshot = next; exportData = data
        } catch { exportError = AppLocalization.text("资料格式无法识别，请稍后重试。") }
    }
}
