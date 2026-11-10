import SwiftUI
import UniformTypeIdentifiers

private struct AccountArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// A separate read-only route. No normal editing, syncing or settlement views are mounted.
struct ExpiredAccountArchiveView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var snapshot: [String: Any] = [:]
    @State private var exportData = Data()
    @State private var busy = false
    @State private var error = ""
    @State private var exporting = false
    @State private var showingDeletion = false
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
                    Button("导出全部资料") { exporting = true }.disabled(exportData.isEmpty || busy)
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
                                        if !text.isEmpty { LabeledContent(AppLocalization.text(field.1), value: field.0 == "service_type" ? AppLocalization.text(text) : text).textSelection(.enabled) }
                                    }
                                }
                                if section.0 == "user_settings" { Text("完整资料包含在导出文件中。").foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("账号已到期 · 资料只读")
            .sheet(isPresented: $showingDeletion) { CloudAccountDeletionView() }
            .fileExporter(isPresented: $exporting, document: AccountArchiveDocument(data: exportData), contentType: .json, defaultFilename: AppLocalization.text("TrvelMA-资料备份")) { result in
                if case .failure(let failure) = result { error = failure.localizedDescription }
            }
            .task(id: auth.currentEmail) { await load() }
        }
    }

    private func title(_ row: [String: Any], fallback: String) -> String {
        for key in ["customer_name","name","title","address","label"] {
            if let value = row[key] as? String, !value.isEmpty { return value }
        }
        return fallback
    }

    @MainActor private func load() async {
        guard !busy else { return }
        let email = auth.currentEmail
        snapshot = [:]; exportData = Data(); error = ""; busy = true
        defer { busy = false }
        do {
            guard let token = await auth.refreshCloudAccessToken() else {
                error = AppLocalization.text("登录状态已失效，请退出并重新登录。"); return
            }
            let data = try await SupabaseAuthClient.readExpiredArchive(accessToken: token)
            guard auth.currentEmail == email, auth.canReadExpiredArchive, !Task.isCancelled else { return }
            let object = try JSONSerialization.jsonObject(with: data)
            guard let archive = object as? [String: Any], archive["read_only"] as? Bool == true else {
                error = AppLocalization.text("资料格式无法识别，请稍后重试。"); return
            }
            snapshot = archive
            exportData = try JSONSerialization.data(withJSONObject: archive, options: [.prettyPrinted,.sortedKeys])
        } catch {
            guard auth.currentEmail == email, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}
