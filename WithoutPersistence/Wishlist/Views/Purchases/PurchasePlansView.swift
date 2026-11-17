import SwiftUI
import StoreKit

extension Notification.Name {
    static let requestPurchasePlans = Notification.Name("TrvelMA.requestPurchasePlans")
}

/// Prepared purchase UI. Not exposed in production navigation while billing is disabled.
struct PurchasePlansView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var auth
    @State private var store = StorePurchaseManager()
    @State private var preparationError = ""
    @State private var isPreparing = true
    @State private var preparationRequest = UUID()
    private var accountScope: String { "\(auth.isCloudAccount):\(auth.currentEmail)" }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if BillingReleaseConfiguration.sandboxAcceptanceBuild {
                        Text("沙盒验收版本，仅供开发测试，不用于正式收费。")
                            .foregroundStyle(.orange)
                    }
                    Text("本地版一次买断；云端版按月或按年订阅，最多4台设备。")
                    Text("本地版不含在线航班查询。")
                    Text("恢复购买仅恢复使用权，不恢复或同步本机业务资料。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !store.salesEnabled { Text("购买暂未开放，当前不会扣款。").foregroundStyle(.secondary) }
                    Text("注册验证后的14天试用不绑定付款方式，到期不会自动扣款。")
                }
                ForEach(store.products, id: \.id) { product in
                    Section(product.displayName) {
                        Text(product.description)
                        if product.id == StoreProductCatalog.monthly { Text(AppLocalization.format("%@ / 月，自动续费", product.displayPrice)) }
                        else if product.id == StoreProductCatalog.yearly { Text(AppLocalization.format("%@ / 年，自动续费", product.displayPrice)) }
                        else { Text(AppLocalization.format("%@，一次买断", product.displayPrice)) }
                        Button { Task { await store.purchase(product) } } label: {
                            if product.id == StoreProductCatalog.local && store.hasLocalPurchase { Text("已购买") }
                            else { Text("购买") }
                        }
                            .disabled(isPreparing || store.isBusy || !store.canPurchase(product))
                    }
                }
                Section {
                    if isPreparing { ProgressView("正在读取购买信息…") }
                    if !isPreparing && (!preparationError.isEmpty || store.products.isEmpty) {
                        Button("重试") { Task { await prepareStore() } }.disabled(store.isBusy)
                    }
                    Button("恢复购买") { Task { await store.restore() } }
                        .disabled(isPreparing || !preparationError.isEmpty || store.isBusy)
                    #if DEBUG && STOREKIT_SANDBOX_ACCEPTANCE
                    if store.canRequestSandboxRefund {
                        Button("读取沙盒交易诊断") { Task { await store.refreshSandboxRefundDiagnostic() } }
                            .disabled(isPreparing || !preparationError.isEmpty || store.isBusy)
                        if !store.sandboxRefundDiagnostic.isEmpty {
                            Text(store.sandboxRefundDiagnostic)
                                .font(.body.monospacedDigit()).foregroundStyle(.primary)
                                .accessibilityIdentifier("sandbox-transaction-diagnostic")
                        }
                        Button("沙盒退款测试") {
                            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                                .first(where: { $0.activationState == .foregroundActive }) else { return }
                            Task { await store.requestSandboxRefund(in: scene) }
                        }
                        .disabled(isPreparing || !preparationError.isEmpty || store.isBusy)
                        Text("仅测试原沙盒交易，不会发起新购买。").font(.footnote).foregroundStyle(.secondary)
                    }
                    #endif
                    Link("管理订阅", destination: URL(string: "https://apps.apple.com/account/subscriptions/")!)
                    Text("订阅按所选周期自动续费。可在Apple订阅管理中取消后续续费，实际条款以购买确认页为准。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("隐私政策", destination: URL(string: "https://trvelma.pages.dev/privacy.html")!)
                    Link("Apple标准使用条款", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    if !preparationError.isEmpty { Text(preparationError).foregroundStyle(.secondary) }
                    if !store.message.isEmpty { Text(store.message).foregroundStyle(.secondary) }
                    if store.isBusy { ProgressView() }
                }
            }
            .navigationTitle("版本与购买")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .task(id: accountScope) { await prepareStore() }
        }
    }

    @MainActor private func prepareStore() async {
        let request = UUID()
        let scope = accountScope
        preparationRequest = request
        isPreparing = true
        preparationError = ""
        store = StorePurchaseManager()
        defer { if preparationRequest == request { isPreparing = false } }
        do {
            let prepared = try await auth.preparePurchaseManager()
            guard !Task.isCancelled, preparationRequest == request, accountScope == scope else { return }
            store = prepared
        } catch {
            guard !Task.isCancelled, preparationRequest == request, accountScope == scope else { return }
            preparationError = error.localizedDescription
        }
    }
}
