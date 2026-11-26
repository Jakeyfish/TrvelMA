import SwiftUI
import UniformTypeIdentifiers

struct AccountArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// A separate read-only route. No normal editing, syncing or settlement views are mounted.
struct ExpiredAccountArchiveView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var readState = ExpiredArchiveReadState()
    private var snapshot: [String: Any] { readState.owner == archiveOwner ? readState.snapshot : [:] }
    private var exportData: Data { readState.owner == archiveOwner ? readState.exportData : Data() }
    private var busy: Bool { readState.busy }
    private var archiveOwner: String { auth.isLoggedIn && auth.isCloudAccount && auth.canReadExpiredArchive ? auth.currentEmail : "" }
    @State private var error = ""
    @State private var exporting = false
    @State private var showingDeletion = false
    @State private var showingPairing = false
    @State private var pairingCode = ""
    @State private var isPairing = false
    private let sections = [("trips","行程"),("customers","客户"),("travel_agencies","旅行社"),("trip_expenses","费用明细"),("customer_contacts","联系方式"),("customer_addresses","客户地址"),("trip_stops","停靠点"),("user_settings","设置与名片资料")]
    private let fields = [("customer_name","客人"),("name","名称"),("appointment_date","接载日期"),("appointment_time","接载时间"),("price","金额"),("tip","小费"),("location_start","起始点"),("location_end","目的地"),("customer_contact","联系方式"),("phone","电话"),("email","邮箱"),("address","地址"),("value","内容"),("label","类别"),("title","项目"),("amount","金额"),("service_type","行程类型"),("flight_info","航班"),("memo","备注"),("travel_agency_name","旅行社"),("travel_agency_order_number","旅行社订单号")]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("已有资料仍可查看和导出。新增、编辑、结算、航班刷新和同步已暂停。")
                    Text("导出文件包含个人及业务资料，请妥善保管。").font(.footnote).foregroundStyle(.secondary)
                    if busy { ProgressView() }
                    if !error.isEmpty { Text(error).foregroundStyle(.red) }
                    Button("导出全部资料") { exporting = true }.disabled(readState.owner != archiveOwner || !readState.canExport)
                    if archiveOwner.lowercased() == "ystechnology02@yahoo.com", !error.isEmpty {
                        Button("恢复只读设备") { pairingCode = ""; showingPairing = true }
                            .disabled(busy || isPairing)
                    }
                    Button("重新加载资料") { Task { await load() } }.disabled(busy)
                    Button("重新检查授权") { Task { await auth.retryServerEntitlementLookup() } }.disabled(busy)
                    if BillingReleaseConfiguration.plansVisible && auth.canManageCloudPurchases {
                        Button("版本与购买") { NotificationCenter.default.post(name: .requestPurchasePlans, object: nil) }
                    }
                    Button("删除云端账号", role: .destructive) { showingDeletion = true }
                    Button("退出登录") { auth.logout() }
                }
                ForEach(sections, id: \.0) { section in
                    let rows = snapshot[section.0] as? [[String: Any]] ?? []
                    Section("\(AppLocalization.text(section.1)) · \(rows.count)") {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            DisclosureGroup(title(row, fallback: AppLocalization.text(section.1))) {
                                ForEach(fields, id: \.0) { field in
                                    if let value = row[field.0], !(value is NSNull) {
                                        let text = String(describing: value)
                                        if !text.isEmpty {
                                            LabeledContent {
                                                if field.0 == "service_type" {
                                                    HStack(spacing: 6) {
                                                        Text(AppLocalization.text(text))
                                                        TripAgencyBadge(orderSource: row["order_source"] as? String ?? "",
                                                                        agencyName: row["travel_agency_name"] as? String ?? "")
                                                    }
                                                } else {
                                                    Text(text)
                                                }
                                            } label: {
                                                Text(AppLocalization.text(field.1))
                                            }
                                            .textSelection(.enabled)
                                        }
                                    }
                                }
                                if section.0 == "user_settings" { Text("完整资料包含在导出文件中。").foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("账号已到期 · 资料只读")
            .alert("恢复只读设备", isPresented: $showingPairing) {
                TextField("配对码", text: $pairingCode)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("取消", role: .cancel) { pairingCode = "" }
                Button("确认") {
                    let code = UUID(uuidString: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines))
                    pairingCode = ""
                    Task { await pairDevice(code) }
                }
            } message: {
                Text("请输入已登记的网页版生成的配对码。")
            }
            .sheet(isPresented: $showingDeletion) { CloudAccountDeletionView() }
            .fileExporter(isPresented: $exporting, document: AccountArchiveDocument(data: exportData), contentType: .json, defaultFilename: AppLocalization.text("TrvelMA-资料备份")) { result in
                if case .failure(let failure) = result { error = failure.localizedDescription }
            }
            .task(id: archiveOwner) {
                if readState.owner != archiveOwner { readState.reset(); error = "" }
                if archiveOwner.isEmpty { readState.reset() } else { await load() }
            }
            .onDisappear { readState.reset() }
        }
    }

    private func title(_ row: [String: Any], fallback: String) -> String {
        for key in ["customer_name","name","title","address","label"] {
            if let value = row[key] as? String, !value.isEmpty { return value }
        }
        return fallback
    }

    @MainActor private func pairDevice(_ code: UUID?) async {
        guard !isPairing, !busy, !archiveOwner.isEmpty else { return }
        guard let code else { error = AppLocalization.text("配对码无效或已过期。"); return }
        let owner = archiveOwner
        isPairing = true
        defer { isPairing = false }
        do {
            let token = await auth.refreshCloudAccessToken()
            guard archiveOwner == owner, let token else { return }
            try await SupabaseAuthClient.completeExpiredDevicePairing(code: code, accessToken: token)
            guard archiveOwner == owner else { return }
            await load()
        } catch {
            guard archiveOwner == owner else { return }
            self.error = AppLocalization.text("恢复只读设备失败，请在网页版重新获取配对码。")
        }
    }

    @MainActor private func load() async {
        guard !busy, !archiveOwner.isEmpty else { return }
        let owner = archiveOwner
        let request = readState.begin(owner: owner)
        error = ""
        do {
            let refreshedToken = await auth.refreshCloudAccessToken()
            guard archiveOwner == owner, readState.isCurrent(request: request, owner: owner), !Task.isCancelled else { return }
            guard let token = refreshedToken else {
                readState.fail(request: request, owner: owner, transient: false)
                error = AppLocalization.text("登录状态已失效，请退出并重新登录。"); return
            }
            let data = try await SupabaseAuthClient.readExpiredArchive(accessToken: token)
            guard archiveOwner == owner, readState.isCurrent(request: request, owner: owner), !Task.isCancelled else { return }
            try readState.accept(data, request: request, owner: owner)
        } catch {
            guard archiveOwner == owner, readState.isCurrent(request: request, owner: owner), !Task.isCancelled else { return }
            let transient: Bool
            if case let SupabaseAuthClient.AuthError.response(statusCode, _) = error {
                transient = statusCode == 429 || (500..<600).contains(statusCode)
            } else if let failure = error as? URLError {
                transient = [.timedOut, .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                             .cannotConnectToHost, .dnsLookupFailed].contains(failure.code)
            } else { transient = false }
            readState.fail(request: request, owner: owner, transient: transient)
            self.error = error is ExpiredArchiveReadState.InvalidArchive
                ? AppLocalization.text("资料格式无法识别，请稍后重试。") : error.localizedDescription
        }
    }
}
