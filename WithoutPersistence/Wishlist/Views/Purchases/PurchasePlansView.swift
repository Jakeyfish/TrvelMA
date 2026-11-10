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
                    if !store.salesEnabled { Text("购买暂未开放，当前不会扣款。").foregroundStyle(.secondary) }
                    Text("注册验证后的14天试用不绑定付款方式，到期不会自动扣款。")
                }
                ForEach(store.products, id: \.id) { product in
                    Section(product.displayName) {
                        Text(product.description)
                        if product.id == StoreProductCatalog.monthly { Text(AppLocalization.format("%@ / 月，自动续费", product.displayPrice)) }
                        else if product.id == StoreProductCatalog.yearly { Text(AppLocalization.format("%@ / 年，自动续费", product.displayPrice)) }
                        else { Text(AppLocalization.format("%@，一次买断", product.displayPrice)) }
                        Button("购买") { Task { await store.purchase(product) } }
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
