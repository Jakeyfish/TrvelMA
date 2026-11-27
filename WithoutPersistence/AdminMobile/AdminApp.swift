import SwiftUI

@main
struct AdminApp: App {
    var body: some Scene { WindowGroup { AdminRoot() } }
}

private func editionName(_ value: String) -> String {
    ["local": "本地版", "cloud": "云端版", "sync": "同步版"][value] ?? value
}
private func statusName(_ value: String) -> String {
    ["active": "有效", "grace": "宽限期", "expired": "已到期", "revoked": "已暂停", "unlicensed": "未授权"][value] ?? value
}
private func purposeName(_ value: String) -> String {
    ["business": "业务账号", "review": "Apple 审核专用", "development": "开发测试", "ordinary": "普通账号"][value] ?? value
}

@MainActor
private final class AdminState: ObservableObject {
    let api = AdminAPI()
    @Published var applications: [Application] = []
    @Published var needsCode = false
    @Published var busy = false
    @Published var message: String?
    @Published var generation = UUID()

    func run(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await operation() }
        catch is CancellationError {}
        catch {
            if let failure = error as? AdminError {
                let recent = failure.message == "ADMIN_RECENT_MFA_REQUIRED"
                if recent || (!applications.isEmpty && failure.status == 401) {
                    applications = []
                    generation = UUID()
                    needsCode = recent && api.factor != nil
                    if !needsCode { api.reset() }
                }
            }
            message = error.localizedDescription
        }
    }
}

private struct AdminRoot: View {
    @StateObject private var state = AdminState()
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                if state.applications.isEmpty {
                    if state.needsCode {
                        Section("二次验证") {
                            TextField("六位验证码", text: $code)
                                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                            Button("验证") {
                                let input = code
                                code = ""
                                Task {
                                    await state.run {
                                        state.applications = try await state.api.verify(input)
                                        if state.applications.isEmpty { state.message = "此账号尚未分配可用应用权限。" }
                                    }
                                }
                            }
                            .disabled(code.utf8.count != 6 || !code.utf8.allSatisfy { (48...57).contains($0) })
                        }
                    } else {
                        Section("管理员登录") {
                            TextField("邮箱", text: $email)
                                .keyboardType(.emailAddress).textContentType(.username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                            SecureField("密码", text: $password).textContentType(.password)
                            Button("登录") {
                                let secret = password
                                password = ""
                                Task {
                                    await state.run {
                                        try await state.api.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: secret)
                                        state.needsCode = true
                                    }
                                }
                            }
                            .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                        }
                    }
                } else {
                    Section("应用") {
                        ForEach(state.applications) { app in
                            NavigationLink {
                                UserDirectory(app: app)
                            } label: {
                                Label(app.name, systemImage: "square.grid.2x2")
                                Spacer()
                                Text(app.environmentLabel).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if state.needsCode || !state.applications.isEmpty {
                    Button("退出登录", role: .destructive) {
                        Task {
                            await state.run {
                                await state.api.logout()
                                state.needsCode = false
                                state.applications = []
                                state.generation = UUID()
                            }
                        }
                    }
                }
            }
            .navigationTitle("云盛应用管理")
        }
        .id(state.generation)
        .environmentObject(state)
        .disabled(state.busy)
        .overlay { if state.busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .tint(Color(red: 0.08, green: 0.35, blue: 0.28))
        .alert("云盛应用管理", isPresented: Binding(get: { state.message != nil }, set: { if !$0 { state.message = nil } })) {
            Button("好") { state.message = nil }
        } message: { Text(state.message ?? "") }
    }
}

private struct UserDirectory: View {
    @EnvironmentObject private var state: AdminState
    let app: Application
    @State private var search = ""
    @State private var appliedSearch = ""
    @State private var offset = 0
    @State private var page: UserPage?

    var body: some View {
        List {
            Section {
                NavigationLink("云豆设置") { FlightBeanPolicyView(app: app) }
                NavigationLink("操作日志") { AuditView(app: app) }
            }
            Section("用户与授权") {
                if let page {
                    if page.users.isEmpty { Text("没有匹配的用户").foregroundStyle(.secondary) }
                    ForEach(page.users) { user in
                        NavigationLink {
                            AccountView(app: app, account: user)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(user.email).font(.headline)
                                Text("\(purposeName(user.purpose)) · \(statusName(user.effectiveStatus))")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Button("上一页") { Task { await load(at: max(0, offset - 25), query: appliedSearch) } }.disabled(offset == 0)
                        Spacer()
                        Button("下一页") { Task { await load(at: offset + 25, query: appliedSearch) } }.disabled(offset + 25 >= page.total)
                    }.buttonStyle(.borderless)
                }
            }
        }
        .navigationTitle(app.name)
        .searchable(text: $search, prompt: "按邮箱搜索")
        .onSubmit(of: .search) { Task { await load(at: 0, query: search) } }
        .task { await load(at: offset, query: appliedSearch) }
        .refreshable { await load(at: offset, query: appliedSearch) }
    }

    private func load(at next: Int, query: String) async {
        let normalized = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150))
        await state.run {
            page = try await state.api.rpc("admin_users", ["p_app": .string(app.id), "p_search": .string(normalized), "p_offset": .number(Double(next))])
            offset = next
            appliedSearch = normalized
        }
    }
}

private struct FlightBeanPolicyView: View {
    @EnvironmentObject private var state: AdminState
    let app: Application
    @State private var policy: FlightBeanPolicy?
    @State private var cost = 2
    @State private var reason = ""
    @State private var confirming = false
    @State private var request = UUID()

    private var trimmedReason: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section(app.name + " · " + app.environmentLabel) {
                Text("手动刷新与接机自动排程共用余额，实际查到结果才扣豆。")
                if let policy {
                    LabeledContent("当前每次扣豆", value: String(policy.cost))
                    if app.writable {
                        Stepper("调整为每次 \(cost) 豆", value: $cost, in: 1...100)
                        TextField("调整原因", text: $reason)
                        Button("保存") { confirming = true }
                            .disabled(cost == policy.cost || !(4...500).contains(trimmedReason.count))
                    }
                } else {
                    Button("加载扣豆设置") { Task { await load() } }
                }
            }
        }
        .disabled(state.busy)
        .navigationTitle("云豆设置")
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: cost) { request = UUID() }
        .onChange(of: reason) { request = UUID() }
        .alert("确认调整扣豆", isPresented: $confirming) {
            Button("取消", role: .cancel) {}
            Button("确认保存") { Task { await save() } }
        } message: {
            Text("\(app.name) · \(app.environmentLabel)，每次从 \(policy?.cost ?? cost) 豆改为 \(cost) 豆。")
        }
    }

    private func load() async {
        await state.run {
            let current: FlightBeanPolicy = try await state.api.rpc("admin_flight_bean_policy", ["p_app": .string(app.id)])
            policy = current
            cost = current.cost
        }
    }

    private func save() async {
        guard let policy, app.writable, (4...500).contains(trimmedReason.count) else { return }
        await state.run {
            let saved: FlightBeanPolicy = try await state.api.rpc("admin_set_flight_bean_policy", [
                "p_app": .string(app.id), "p_cost": .number(Double(cost)),
                "p_expected": .string(policy.updatedAt), "p_request": .string(request.uuidString),
                "p_reason": .string(trimmedReason)
            ])
            self.policy = saved
            reason = ""
            request = UUID()
        }
    }
}

private struct AccountView: View {
    @EnvironmentObject private var state: AdminState
    let app: Application
    let account: Account
    @State private var detail: AccountDetail?
    @State private var adjustment = false
    @State private var selectedDevice: Device?
    @State private var notice: String?

    var body: some View {
        List {
            Section {
                Text(account.email).font(.headline)
                Text("\(purposeName(account.purpose)) · \(app.environmentLabel)").foregroundStyle(.secondary)
                if let notice { Text(notice).foregroundStyle(.tint) }
            }
            if let detail {
                Section("当前授权") {
                    if let e = detail.entitlement {
                        LabeledContent("版本", value: editionName(e.edition))
                        LabeledContent("状态", value: statusName(e.status != "revoked" && AdminDate.parse(e.expiresAt).map { $0 <= Date() } == true ? "expired" : e.status))
                        LabeledContent("到期时间", value: AdminDate.display(e.expiresAt, fallback: "无到期日"))
                        LabeledContent("设备上限", value: String(e.maxDevices))
                    } else { Text("未授权") }
                    if app.writable { Button("调整授权") { adjustment = true } }
                }
                Section("设备") {
                    if detail.devices.isEmpty { Text("无设备记录") }
                    ForEach(detail.devices) { device in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(device.deviceType)
                            Text("最后活动 \(AdminDate.display(device.lastSeenAt))").font(.caption).foregroundStyle(.secondary)
                            if device.revokedAt != nil { Text("已释放").font(.caption) }
                            else if app.writable { Button("释放此设备", role: .destructive) { selectedDevice = device }.buttonStyle(.borderless) }
                        }
                    }
                }
                Section("已验签交易") {
                    if detail.transactions.isEmpty { Text("无交易记录") }
                    ForEach(Array(detail.transactions.enumerated()), id: \.offset) { _, transaction in
                        VStack(alignment: .leading) {
                            Text(transaction.productId)
                            Text("\(transaction.environment) · \(AdminDate.display(transaction.purchasedAt))").font(.caption)
                            if let expiry = transaction.expiresAt { Text("到期 \(AdminDate.display(expiry))").font(.caption) }
                            if let revoked = transaction.revokedAt { Text("撤销 \(AdminDate.display(revoked))").font(.caption) }
                        }
                    }
                }
            }
        }
        .navigationTitle("账号详情")
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $adjustment) {
            if let detail {
                GrantView(app: app, account: account, previous: detail.entitlement) {
                    adjustment = false
                    notice = "授权已更新并记录审计。"
                    await load()
                }
            }
        }
        .sheet(item: $selectedDevice) { device in
            ReleaseView(app: app, account: account, device: device) {
                selectedDevice = nil
                notice = "设备已释放并记录审计。"
                await load()
            }
        }
    }

    private func load() async {
        await state.run { detail = try await state.api.rpc("admin_user_detail", ["p_app": .string(app.id), "p_owner": .string(account.id)]) }
    }
}

private struct GrantView: View {
    @EnvironmentObject private var state: AdminState
    @Environment(\.dismiss) private var dismiss
    let app: Application
    let account: Account
    let previous: Entitlement?
    let completed: () async -> Void
    @State private var draft: GrantDraft
    @State private var confirmedDraft: GrantDraft?
    @State private var request = UUID()

    init(app: Application, account: Account, previous: Entitlement?, completed: @escaping () async -> Void) {
        self.app = app; self.account = account; self.previous = previous; self.completed = completed
        _draft = State(initialValue: GrantDraft(previous))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(app.name + " · " + app.environmentLabel) { Text(account.email) }
                if let pending = confirmedDraft {
                    Section("当前授权") {
                        if let previous {
                            LabeledContent("版本", value: editionName(previous.edition))
                            LabeledContent("状态", value: statusName(previous.status))
                            LabeledContent("设备上限", value: String(previous.maxDevices))
                            LabeledContent("到期", value: AdminDate.display(previous.expiresAt, fallback: "无到期日"))
                        } else { Text("未授权") }
                    }
                    Section("新授权") {
                        LabeledContent("版本", value: editionName(pending.edition))
                        LabeledContent("状态", value: statusName(pending.status))
                        LabeledContent("设备上限", value: String(pending.devices))
                        LabeledContent("到期", value: pending.expiry?.formatted() ?? "无到期日")
                        LabeledContent("原因", value: pending.reason)
                    }
                    Button("确认调整") {
                        Task {
                            var saved = false
                            await state.run {
                                let _: JSONValue = try await state.api.rpc("admin_set_entitlement", pending.parameters(app: app, account: account, previous: previous, request: request))
                                saved = true
                            }
                            if saved { await completed() }
                        }
                    }
                    Button("返回编辑") { confirmedDraft = nil }
                } else {
                    Picker("版本", selection: $draft.edition) {
                        ForEach(["local", "cloud", "sync"], id: \.self) { Text(editionName($0)).tag($0) }
                    }
                    Picker("状态", selection: $draft.status) {
                        ForEach(["active", "grace", "expired", "revoked"], id: \.self) { Text(statusName($0)).tag($0) }
                    }
                    Stepper("设备上限 \(draft.devices)", value: $draft.devices, in: 1...100)
                    Toggle("设定到期时间", isOn: Binding(get: { draft.expiry != nil }, set: { enabled in
                        draft.expiry = enabled ? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date() : nil
                    }))
                    if draft.expiry != nil {
                        DatePicker("到期时间", selection: Binding(get: { draft.expiry ?? Date() }, set: { draft.expiry = $0 }))
                    }
                    TextField("操作原因（4–500 字）", text: $draft.reason, axis: .vertical)
                    Button("核对变更") { request = UUID(); confirmedDraft = draft }.disabled(!draft.valid)
                }
            }
            .navigationTitle(confirmedDraft == nil ? "调整授权" : "确认授权调整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .disabled(state.busy)
        }
        .interactiveDismissDisabled(state.busy)
    }
}

private struct ReleaseView: View {
    @EnvironmentObject private var state: AdminState
    @Environment(\.dismiss) private var dismiss
    let app: Application
    let account: Account
    let device: Device
    let completed: () async -> Void
    @State private var reason = ""
    @State private var submittedReason: String?
    @State private var request = UUID()

    var body: some View {
        NavigationStack {
            Form {
                Section(app.name + " · " + app.environmentLabel) {
                    Text(account.email)
                    Text(device.deviceType)
                    Text(device.deviceId).font(.caption).foregroundStyle(.secondary)
                    Text("释放设备登记后，该设备需重新登记。当前登录会话不会被强制退出。")
                }
                TextField("操作原因（4–500 字）", text: $reason, axis: .vertical)
                Button("确认释放", role: .destructive) {
                    if submittedReason != cleanReason { request = UUID(); submittedReason = cleanReason }
                    Task {
                        var saved = false
                        await state.run {
                            let _: JSONValue = try await state.api.rpc("admin_release_device", [
                                "p_app": .string(app.id), "p_owner": .string(account.id), "p_device": .string(device.deviceId),
                                "p_last_seen": .optional(device.lastSeenAt), "p_reason": .string(cleanReason), "p_request": .string(request.uuidString)
                            ])
                            saved = true
                        }
                        if saved { await completed() }
                    }
                }.disabled(!(4...500).contains(cleanReason.count))
            }
            .navigationTitle("释放设备占用").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .disabled(state.busy)
        }
        .interactiveDismissDisabled(state.busy)
    }
    private var cleanReason: String { reason.trimmingCharacters(in: .whitespacesAndNewlines) }
}

private struct AuditView: View {
    @EnvironmentObject private var state: AdminState
    let app: Application
    @State private var entries: [AuditEntry]?
    @State private var offset = 0

    var body: some View {
        List {
            if let entries {
                if entries.isEmpty { Text("此页无操作记录").foregroundStyle(.secondary) }
                ForEach(entries) { entry in
                    DisclosureGroup {
                        LabeledContent("操作者", value: entry.actor)
                        LabeledContent("目标", value: entry.target ?? "—")
                        LabeledContent("原因", value: entry.reason ?? "—")
                        if let before = entry.beforeValue { Text("变更前"); Text(before.formatted).font(.caption.monospaced()) }
                        if let after = entry.afterValue { Text("变更后"); Text(after.formatted).font(.caption.monospaced()) }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(["view_account": "查看账号", "set_entitlement": "调整授权", "release_device": "释放设备"][entry.action] ?? entry.action)
                            Text(AdminDate.display(entry.occurredAt)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Button("上一页") { Task { await load(at: max(0, offset - 25)) } }.disabled(offset == 0)
                    Spacer()
                    Button("下一页") { Task { await load(at: offset + 25) } }.disabled(entries.count < 25)
                }.buttonStyle(.borderless)
            }
        }
        .navigationTitle("操作日志")
        .task { await load(at: offset) }
        .refreshable { await load(at: offset) }
    }
    private func load(at next: Int) async {
        await state.run {
            entries = try await state.api.rpc("admin_audit", ["p_app": .string(app.id), "p_offset": .number(Double(next))])
            offset = next
        }
    }
}
