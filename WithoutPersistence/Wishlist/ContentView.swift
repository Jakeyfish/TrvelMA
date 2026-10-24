/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The top-level tab navigation for the app.
*/

import SwiftUI
import SwiftData
import UIKit
import MapKit
import PhotosUI

struct ContentView: View {
    @Environment(AppLanguageSettings.self) private var languageSettings
    @State private var selectedTab: MainTab = .home

    var body: some View {
        Group{
            // TabView caches tab labels. Rebuild it when the in-app language
            // changes so the tab bar cannot keep labels from the prior locale.
            TabView(selection: $selectedTab) {
                // Use a custom label with verbatim text. `Tab(_:systemImage:)`
                // accepts a LocalizedStringKey, so passing a String that was
                // already localized can cause SwiftUI to localize that result
                // a second time using the system language.
                WishlistView()
                    .toolbar(UIDevice.current.userInterfaceIdiom == .pad ? .hidden : .visible, for: .tabBar)
                    .tabItem {
                        tabLabel("主页", systemImage: "house.fill")
                    }
                    .tag(MainTab.home)

                TripsPageView()
                    .toolbar(UIDevice.current.userInterfaceIdiom == .pad ? .hidden : .visible, for: .tabBar)
                    .tabItem {
                        tabLabel("行程", systemImage: "books.vertical")
                    }
                    .tag(MainTab.trips)

                BusinessCardView()
                    .toolbar(UIDevice.current.userInterfaceIdiom == .pad ? .hidden : .visible, for: .tabBar)
                    .tabItem {
                        tabLabel("名片", systemImage: "person.text.rectangle.fill")
                    }
                    .tag(MainTab.card)

                WalletView()
                    .toolbar(UIDevice.current.userInterfaceIdiom == .pad ? .hidden : .visible, for: .tabBar)
                    .tabItem {
                        tabLabel("钱包", systemImage: "wallet.bifold.fill")
                    }
                    .tag(MainTab.wallet)

                CustomerListView()
                    .toolbar(UIDevice.current.userInterfaceIdiom == .pad ? .hidden : .visible, for: .tabBar)
                    .tabItem {
                        tabLabel("客户", systemImage: "person.crop.rectangle.badge.plus.fill")
                    }
                    .tag(MainTab.customers)

            }
            .id(languageSettings.identifier)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    ipadBottomBar
                }
            }
        }
    }

    private var ipadBottomBar: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                        Text(tabLabelTitle(tab))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background {
                        if selectedTab == tab {
                            Capsule().fill(Color.accentColor.opacity(0.12))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tabLabelTitle(tab))
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private func tabLabelTitle(_ tab: MainTab) -> String {
        let title: String
        switch tab {
        case .home: title = "主页"
        case .trips: title = "行程"
        case .card: title = "名片"
        case .wallet: title = "钱包"
        case .customers: title = "客户"
        }
        return localizedTabTitle(title)
    }

    private func tabLabel(_ title: String, systemImage: String) -> some View {
        Label {
            Text(verbatim: localizedTabTitle(title))
        } icon: {
            Image(systemName: systemImage)
        }
    }

    private func localizedTabTitle(_ title: String) -> String {
        let localizedTitle: String
        switch languageSettings.selectedLanguage {
        case .simplifiedChinese:
            localizedTitle = title
        case .traditionalChinese:
            switch title {
            case "主页": localizedTitle = "主頁"
            case "行程": localizedTitle = "行程"
            case "名片": localizedTitle = "名片"
            case "钱包": localizedTitle = "錢包"
            case "客户": localizedTitle = "客戶"
            default: localizedTitle = title
            }
        case .english:
            switch title {
            case "主页": localizedTitle = "Home"
            case "行程": localizedTitle = "Trips"
            case "名片": localizedTitle = "Contacts"
            case "钱包": localizedTitle = "Wallet"
            case "客户": localizedTitle = "Customers"
            default: localizedTitle = title
            }
        case .spanish:
            switch title {
            case "主页": localizedTitle = "Inicio"
            case "行程": localizedTitle = "Viajes"
            case "名片": localizedTitle = "Contactos"
            case "钱包": localizedTitle = "Cartera"
            case "客户": localizedTitle = "Clientes"
            default: localizedTitle = title
            }
        case .japanese:
            switch title {
            case "主页": localizedTitle = "ホーム"
            case "行程": localizedTitle = "旅行"
            case "名片": localizedTitle = "連絡先"
            case "钱包": localizedTitle = "ウォレット"
            case "客户": localizedTitle = "顧客"
            default: localizedTitle = title
            }
        case .korean:
            switch title {
            case "主页": localizedTitle = "홈"
            case "行程": localizedTitle = "여행"
            case "名片": localizedTitle = "연락처"
            case "钱包": localizedTitle = "지갑"
            case "客户": localizedTitle = "고객"
            default: localizedTitle = title
            }
        }
        return localizedTitle
    }
}

private enum MainTab: Hashable, CaseIterable {
    case home, trips, card, wallet, customers

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .trips: "books.vertical"
        case .card: "person.text.rectangle.fill"
        case .wallet: "wallet.bifold.fill"
        case .customers: "person.crop.rectangle.badge.plus.fill"
        }
    }
}


struct CustomerListView: View {
    @Environment(AppLanguageSettings.self) private var languageSettings
    @Environment(AuthViewModel.self) private var auth
    @Query private var customers: [Custumer]
    @State private var isAddingCustomer = false
    @State private var selectedFilter: CustomerListFilter = .all
    @State private var searchText = ""

    init() {
        let scope = DataOwnership.activeScope
        _customers = Query(filter: #Predicate { $0.ownerScope == scope })
    }

    private var sortedCustomers: [Custumer] {
        customers.sorted { $0.updateAt > $1.updateAt }
    }

    private var filteredCustomers: [Custumer] {
        let byCategory = sortedCustomers.filter { customer in
            switch selectedFilter {
            case .all: true
            case .regular: customer.customerCategory == 1
            case .agency: customer.customerCategory == 2
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return byCategory }
        return byCategory.filter { customer in
            let categoryName = customer.customerCategory == 2 ? "旅行社" : "普通客户"
            let searchableValues = [customer.name, customer.email, customer.csource, customer.remark, customer.languagePreference, categoryName, String(customer.type)]
                + customer.connecttype.flatMap { [$0.connectlable, $0.connecttype] }
                + customer.addresses.flatMap { [$0.addlable, $0.addresses] }
            return searchableValues.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var isOnlineOnly: Bool {
        auth.serverEntitlement?.edition == .cloud && auth.serverEntitlement?.isCurrentlyActive == true
    }

    var body: some View {
        Group {
            if isOnlineOnly {
                CloudCustomerDirectoryView()
            } else {
                localBody
            }
        }
    }

    private var localBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CustomerDirectoryControls(
                    resultCount: filteredCustomers.count,
                    selectedFilter: $selectedFilter,
                    searchText: $searchText,
                    onAdd: { isAddingCustomer = true }
                )

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredCustomers, id: \.uuid) { customer in
                            NavigationLink {
                                CustomerBrowseView(customer: customer)
                            } label: {
                            CustomerDirectoryRow(
                                name: customer.name,
                                category: customer.customerCategory,
                            ) {
                                CustomerAvatarView(path: customer.avatarUrl, size: 48, fallbackName: customer.name)
                            }
                            }
                            .buttonStyle(.plain)
                        }
                        if filteredCustomers.isEmpty {
                            ContentUnavailableView(searchText.isEmpty ? "暂无客户" : "没有找到客户", systemImage: searchText.isEmpty ? "person.crop.rectangle" : "magnifyingglass")
                                .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .adaptiveFormPresentation(isPresented: $isAddingCustomer) {
                NavigationStack {
                    CustomerDetailView(customer: nil)
                }
            }
        }
        .font(.system(size: 15))
    }

}

private struct CustomerContactSnapshot: Identifiable {
    let id = UUID()
    let type: String
    let value: String
    let isDefault: Bool
}

private struct CustomerAddressSnapshot: Identifiable {
    let id = UUID()
    let type: String
    let value: String
    let isDefault: Bool
}

/// A value snapshot prevents a pushed detail/editor screen from retaining a
/// SwiftData object while another device's sync changes or removes that row.
private struct CustomerProfileSnapshot {
    let id: String
    let ownerScope: String
    let name: String
    let email: String
    let avatarUrl: String
    let customerCategory: Int
    let travelAgencyCode: String
    let travelAgencyName: String
    let languagePreference: String
    let remark: String
    let contacts: [CustomerContactSnapshot]
    let addresses: [CustomerAddressSnapshot]

    init(_ customer: Custumer) {
        id = customer.uuid
        ownerScope = customer.ownerScope
        name = customer.name
        email = customer.email
        avatarUrl = customer.avatarUrl
        customerCategory = customer.customerCategory
        travelAgencyCode = customer.travelAgencyCode
        travelAgencyName = customer.travelAgencyName
        languagePreference = customer.languagePreference
        remark = customer.remark
        contacts = customer.connecttype.map {
            CustomerContactSnapshot(type: $0.connectlable, value: $0.connecttype, isDefault: $0.isDefault)
        }
        addresses = customer.addresses.map {
            CustomerAddressSnapshot(type: $0.addlable, value: $0.addresses, isDefault: $0.isDefault)
        }
    }
}

private struct CustomerBrowseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(NavigationProvider.defaultsKey) private var defaultNavigationProvider = NavigationProvider.appleMaps.rawValue
    @AppStorage(BaseCurrencyCatalog.countryCodeKey) private var baseCurrencyCountry = BaseCurrencyCatalog.defaultCountryCode
    @Query private var tripBookings: [TripBookingRecord]
    @Query private var allCustomers: [Custumer]
    @Query private var syncConflicts: [CloudSyncConflict]
    let customer: CustomerProfileSnapshot
    private let registryCustomerID: String
    private let registryOwnerScope: String
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    init(customer: Custumer) {
        let snapshot = CustomerProfileSnapshot(customer)
        self.customer = snapshot
        registryCustomerID = snapshot.id
        registryOwnerScope = snapshot.ownerScope
        let scope = snapshot.ownerScope
        _tripBookings = Query(filter: #Predicate { $0.ownerScope == scope })
        _allCustomers = Query(filter: #Predicate { $0.ownerScope == scope })
        _syncConflicts = Query(filter: #Predicate { $0.ownerScope == scope && $0.tableName == "customers" })
    }

    @MainActor private var currentCustomer: CustomerProfileSnapshot {
        allCustomers.first(where: { $0.uuid == customer.id }).map(CustomerProfileSnapshot.init) ?? customer
    }

    private var hasPendingRemoteDeletion: Bool {
        syncConflicts.contains {
            $0.recordID.caseInsensitiveCompare(customer.id) == .orderedSame && $0.isRemoteDeletion
        }
    }

    private var customerTrips: [TripBookingRecord] {
        let isUniqueCustomerName = allCustomers.filter { $0.name == currentCustomer.name }.count == 1
        return tripBookings
            .filter { booking in
                guard !booking.isCancelled else { return false }
                if booking.customerUUID == customer.id { return true }
                return booking.customerUUID == nil
                    && isUniqueCustomerName
                    && booking.customerName == currentCustomer.name
            }
            .sorted { $0.appointmentDate > $1.appointmentDate }
    }

    private var hasAnyTripHistory: Bool {
        let isUniqueCustomerName = allCustomers.filter { $0.name == currentCustomer.name }.count == 1
        return tripBookings.contains { booking in
            if booking.customerUUID == customer.id { return true }
            return booking.customerUUID == nil
                && isUniqueCustomerName
                && booking.customerName == currentCustomer.name
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    CustomerAvatarView(path: currentCustomer.avatarUrl, size: 76, fallbackName: currentCustomer.name)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentCustomer.name).font(.headline.weight(.semibold))
                        Text(currentCustomer.customerCategory == 2 ? "旅行社" : "普通客户")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("语言喜好", value: AppLanguage(rawValue: currentCustomer.languagePreference)?.nativeName ?? currentCustomer.languagePreference)
                if currentCustomer.customerCategory == 2 {
                    HStack(spacing: 12) {
                        compactCustomerValue("旅行社代码", currentCustomer.travelAgencyCode.isEmpty ? "未选择" : currentCustomer.travelAgencyCode)
                        compactCustomerValue("旅行社名称", currentCustomer.travelAgencyName.isEmpty ? "未选择" : currentCustomer.travelAgencyName)
                    }
                }
            }

            if hasPendingRemoteDeletion {
                Section {
                    Label("此客户已在另一台设备删除，请先处理同步冲突后再查看或编辑。", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section("联系方式") {
                ForEach(currentCustomer.contacts) { contact in
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(contact.type))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        if contact.isDefault {
                            Text("默认")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.10), in: Capsule())
                        }
                        Text(contact.value)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if contact.type == "电话" {
                            Button { openContactURL("tel://\(contact.value)") } label: {
                                Image(systemName: "phone.fill")
                            }
                            .accessibilityLabel("拨打电话")
                            Button { openContactURL("sms:\(contact.value)") } label: {
                                Image(systemName: "message.fill")
                            }
                            .accessibilityLabel("发送信息")
                        } else if contact.type == "邮箱" {
                            Button { openContactURL("mailto:\(contact.value)") } label: {
                                Image(systemName: "envelope.fill")
                            }
                            .accessibilityLabel("发送邮件")
                        }
                    }
                    .font(.system(size: 12))
                    .padding(.vertical, 3)
                }
                if currentCustomer.contacts.isEmpty && currentCustomer.email.isEmpty {
                    Text("暂无联系方式").foregroundStyle(.secondary)
                } else if currentCustomer.contacts.isEmpty {
                    HStack {
                        Text("邮箱")
                        Spacer()
                        Text(currentCustomer.email).foregroundStyle(.secondary)
                    }
                }
            }

            Section("常用地址") {
                ForEach(currentCustomer.addresses) { address in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(LocalizedStringKey(address.type)).font(.footnote.weight(.medium))
                            if address.isDefault { Text("默认").font(.system(size: 11)).foregroundStyle(Color.accentColor) }
                        }
                        Button { openMap(address.value) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(address.value)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Label("使用默认导航", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
                if currentCustomer.addresses.isEmpty { Text("暂无常用地址").foregroundStyle(.secondary) }
            }

            Section("备注") {
                Text(currentCustomer.remark.isEmpty ? "暂无备注" : currentCustomer.remark)
                    .foregroundStyle(currentCustomer.remark.isEmpty ? .secondary : .primary)
            }

            Section {
                if customerTrips.isEmpty {
                    Text("暂无出行记录")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customerTrips, id: \.id) { booking in
                        CustomerTripRecordRow(booking: booking, currencyCountry: baseCurrencyCountry)
                    }
                }
            } header: {
                Text("出行记录")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .navigationTitle("客户资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if !hasPendingRemoteDeletion {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        CustomerDetailView(profile: currentCustomer)
                    } label: {
                        Label("编辑", systemImage: "pencil")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    if hasAnyTripHistory {
                        errorMessage = "该客户已有出行记录，不能删除。"
                    } else {
                        isConfirmingDelete = true
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("删除客户")
            }
        }
        .confirmationDialog("确定删除该客户？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteCustomer() }
            Button("取消", role: .cancel) {}
        }
        .alert("提示", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .font(.system(size: 15))
        .onAppear {
            SyncEditRegistry.begin(table: "customers", id: registryCustomerID, scope: registryOwnerScope)
        }
        .onDisappear {
            SyncEditRegistry.end(table: "customers", id: registryCustomerID, scope: registryOwnerScope)
        }
    }

    private func compactCustomerValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    private func openContactURL(_ value: String) {
        let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        if let url = URL(string: encoded) { openURL(url) }
    }

    private func openMap(_ address: String) {
        let provider = NavigationProvider(rawValue: defaultNavigationProvider) ?? .appleMaps
        guard let url = provider.directionsURL(for: address) else { return }
        openURL(url)
    }

    private func deleteCustomer() {
        let customerID = customer.id
        let ownerScope = customer.ownerScope
        let descriptor = FetchDescriptor<Custumer>(predicate: #Predicate {
            $0.uuid == customerID && $0.ownerScope == ownerScope
        })
        do {
            guard let current = try modelContext.fetch(descriptor).first else {
                dismiss()
                return
            }
            SupabaseDataSync.recordDeletion(table: "customers", id: customerID, context: modelContext)
            modelContext.delete(current)
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private func customerTripRecords(
    for customer: Custumer,
    customers: [Custumer],
    bookings: [TripBookingRecord]
) -> [TripBookingRecord] {
    let isUniqueCustomerName = customers.filter { $0.name == customer.name }.count == 1
    return bookings
        .filter { booking in
            guard !booking.isCancelled else { return false }
            if booking.customerUUID == customer.uuid { return true }
            return booking.customerUUID == nil
                && isUniqueCustomerName
                && booking.customerName == customer.name
        }
        .sorted { $0.appointmentDate > $1.appointmentDate }
}

private struct CustomerTripRecordRow: View {
    let booking: TripBookingRecord
    let currencyCountry: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            valueColumn("出行日期", value: booking.appointmentDate.formatted(date: .numeric, time: .omitted))
                .frame(maxWidth: .infinity, alignment: .leading)
            valueColumn("目的地", value: booking.locationEnd.isEmpty ? "未填写" : booking.locationEnd)
                .frame(maxWidth: .infinity, alignment: .leading)
            valueColumn("车费", value: BaseCurrencyCatalog.format(booking.price, countryCode: currencyCountry))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .font(.system(size: 11))
    }

    private func valueColumn(_ title: String, value: String) -> some View {
        VStack(alignment: title == "车费" ? .trailing : .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CustomerAvatarView: View {
    let path: String
    let size: CGFloat
    let fallbackName: String

    private var imageData: Data? {
        guard !path.isEmpty else { return nil }
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
        return try? Data(contentsOf: url)
    }

    var body: some View {
        CustomerAvatarImage(data: imageData, name: fallbackName, size: size)
    }
}

private struct CustomerDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private let isNewCustomer: Bool
    private let registryCustomerID: String?
    private let registryOwnerScope: String?
    @State private var name: String
    @State private var avatarData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var customerCategory: Int
    @State private var travelAgencyCode: String
    @State private var travelAgencyName: String
    @State private var isShowingAgencyPicker = false
    @State private var languagePreference: String
    @State private var contacts: [ContactDraft]
    @State private var addresses: [AddressDraft]
    @State private var remark: String
    @State private var message: String?
    @State private var addressSearchTarget: UUID?
    @StateObject private var addressSearcher = AddressAutocompleteSearcher()

    init(customer: Custumer?) {
        self.init(profile: customer.map { CustomerProfileSnapshot($0) })
    }

    init(profile: CustomerProfileSnapshot?) {
        isNewCustomer = profile == nil
        registryCustomerID = profile?.id
        registryOwnerScope = profile?.ownerScope
        _name = State(initialValue: profile?.name ?? "")
        _avatarData = State(initialValue: Self.loadAvatar(profile?.avatarUrl ?? ""))
        _customerCategory = State(initialValue: profile?.customerCategory ?? 1)
        _travelAgencyCode = State(initialValue: profile?.travelAgencyCode ?? "")
        _travelAgencyName = State(initialValue: profile?.travelAgencyName ?? "")
        _languagePreference = State(initialValue: profile?.languagePreference ?? "zh-Hans")
        var savedContacts = profile?.contacts.map {
            ContactDraft(type: $0.type, value: $0.value, isDefault: $0.isDefault)
        } ?? []
        if savedContacts.isEmpty, let email = profile?.email, !email.isEmpty {
            savedContacts = [ContactDraft(type: "邮箱", value: email)]
        }
        if !savedContacts.isEmpty, !savedContacts.contains(where: { $0.isDefault }) {
            savedContacts[0].isDefault = true
        }
        if let selected = savedContacts.firstIndex(where: { $0.isDefault }) {
            for index in savedContacts.indices { savedContacts[index].isDefault = index == selected }
        }
        var savedAddresses = profile?.addresses.map {
            AddressDraft(type: $0.type, value: $0.value, isDefault: $0.isDefault)
        } ?? []
        if !savedAddresses.isEmpty, !savedAddresses.contains(where: { $0.isDefault }) {
            savedAddresses[0].isDefault = true
        }
        if let selected = savedAddresses.firstIndex(where: { $0.isDefault }) {
            for index in savedAddresses.indices { savedAddresses[index].isDefault = index == selected }
        }
        _contacts = State(initialValue: savedContacts)
        _addresses = State(initialValue: savedAddresses)
        _remark = State(initialValue: profile?.remark ?? "")
    }

    private let contactTypes = ["电话", "微信", "邮箱", "WhatsApp", "LINE"]
    private let addressTypes = ["家", "公司", "其他"]

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    VStack(spacing: 8) {
                        Group {
                            if let avatarData, let image = UIImage(data: avatarData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .foregroundStyle(Color.accentColor.opacity(0.65))
                            }
                        }
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 1))
                        Label(avatarData == nil ? "添加照片" : "更换照片", systemImage: "camera")
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }

            Section("基本信息") {
                SystemIMETextField(text: $name, placeholder: "客户名称")
                VStack(alignment: .leading, spacing: 10) {
                    Text("客户类型")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        customerTypeOption(
                            "普通客户",
                            subtitle: "个人与家庭出行",
                            icon: "person.fill",
                            value: 1
                        )
                        customerTypeOption(
                            "旅行社",
                            subtitle: "团队与机构订单",
                            icon: "building.2.fill",
                            value: 2
                        )
                    }
                }
                Picker("语言喜好", selection: $languagePreference) {
                    ForEach(AppLanguage.options) { language in
                        Text(language.nativeName).tag(language.rawValue)
                    }
                }
            }

            if customerCategory == 2 {
                Section("旅行社信息") {
                    Button { isShowingAgencyPicker = true } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text("旅行社代码")
                                Spacer()
                                Text(travelAgencyCode.isEmpty ? "点击选择" : travelAgencyCode)
                                    .foregroundStyle(travelAgencyCode.isEmpty ? Color.accentColor : Color.secondary)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            HStack {
                                Text("旅行社名称")
                                Spacer()
                                Text(travelAgencyName.isEmpty ? "点击选择" : travelAgencyName)
                                    .foregroundStyle(travelAgencyName.isEmpty ? Color.accentColor : Color.secondary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                ForEach($contacts) { $contact in
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 8) {
                            Menu {
                                ForEach(contactTypes, id: \.self) { type in
                                    Button {
                                        contact.type = type
                                    } label: {
                                        if contact.type == type {
                                            Label(LocalizedStringKey(type), systemImage: "checkmark")
                                        } else {
                                            Text(LocalizedStringKey(type))
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(LocalizedStringKey(contact.type))
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                }
                                .foregroundStyle(Color.accentColor)
                                .fixedSize()
                            }

                            SystemIMETextField(
                                text: $contact.value,
                                placeholder: "输入联系方式",
                                keyboardType: contact.type == "电话" ? .phonePad : (contact.type == "邮箱" ? .emailAddress : .default),
                                capitalization: contact.type == "邮箱" ? .none : .sentences,
                                autocorrection: contact.type == "邮箱" ? .no : .default
                            )

                        }

                        HStack(spacing: 12) {
                            if contact.type == "电话", !contact.value.isEmpty {
                                Button { openSystemURL("tel://\(contact.value)") } label: { Image(systemName: "phone.fill") }
                                    .accessibilityLabel("拨打电话")
                                Button { openSystemURL("sms:\(contact.value)") } label: { Image(systemName: "message.fill") }
                                    .accessibilityLabel("发送信息")
                            } else if contact.type == "邮箱", !contact.value.isEmpty {
                                Button { openSystemURL("mailto:\(contact.value)") } label: { Image(systemName: "envelope.fill") }
                                    .accessibilityLabel("发送邮件")
                            }
                            Spacer(minLength: 0)
                            Button(role: .destructive) {
                                removeContact(contact.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("删除联系方式")

                            Button {
                                setDefaultContact(contact.id)
                            } label: {
                                Label("默认", systemImage: contact.isDefault ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 12))
                                    .foregroundStyle(contact.isDefault ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(contact.isDefault ? .isSelected : [])
                        }
                    }
                }
                Button { addContact() } label: {
                    Label("增加联系方式", systemImage: "plus.circle")
                }
            } header: { Text("联系方式") }

            Section {
                ForEach($addresses) { $address in
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 8) {
                            Menu {
                                ForEach(addressTypes, id: \.self) { type in
                                    Button {
                                        address.type = type
                                    } label: {
                                        if address.type == type {
                                            Label(LocalizedStringKey(type), systemImage: "checkmark")
                                        } else {
                                            Text(LocalizedStringKey(type))
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(LocalizedStringKey(address.type))
                                    Image(systemName: "chevron.down")
                                        .font(.caption2.weight(.semibold))
                                }
                                .foregroundStyle(Color.accentColor)
                                .fixedSize()
                            }

                            AddressSuggestionField(text: $address.value, searcher: addressSearcher, isActive: addressSearchTarget == address.id) {
                                addressSearchTarget = address.id
                            } onSelect: { selected in
                                address.value = selected
                                addressSearcher.searchQuery = ""
                                addressSearchTarget = nil
                            }
                            .layoutPriority(1)
                        }

                        HStack(spacing: 12) {
                            Button(role: .destructive) {
                                removeAddress(address.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("删除常用地址")

                            Button {
                                setDefaultAddress(address.id)
                            } label: {
                                Label("默认", systemImage: address.isDefault ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 12))
                                    .foregroundStyle(address.isDefault ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(address.isDefault ? .isSelected : [])
                        }
                    }
                }
                Button { addAddress() } label: {
                    Label("增加常用地址", systemImage: "plus.circle")
                }
            } header: { Text("常用地址") }

            Section("备注（最多 256 字）") {
                LimitedIMETextEditor(text: $remark, maxLength: 256)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 100)
                Text("\(remark.count)/256")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .font(.system(size: 15))
        .navigationTitle(isNewCustomer ? "新增客户" : "编辑客户")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { saveCustomer() }
                    .fontWeight(.semibold)
            }
        }
        .alert("提示", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("确定", role: .cancel) { message = nil }
        } message: { Text(message ?? "") }
        .sheet(isPresented: $isShowingAgencyPicker) {
            TravelAgencySelectionView { agency in
                travelAgencyCode = agency.agencyCode
                travelAgencyName = agency.name
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                do {
                    avatarData = try await item.loadTransferable(type: Data.self)
                } catch {
                    message = "无法读取所选照片。"
                }
            }
        }
        .onAppear {
            if let registryCustomerID, let registryOwnerScope {
                SyncEditRegistry.begin(table: "customers", id: registryCustomerID, scope: registryOwnerScope)
            }
        }
        .onDisappear {
            if let registryCustomerID, let registryOwnerScope {
                SyncEditRegistry.end(table: "customers", id: registryCustomerID, scope: registryOwnerScope)
            }
        }
    }

    private func customerTypeOption(_ title: String, subtitle: String, icon: String, value: Int) -> some View {
        let isSelected = customerCategory == value
        return Button {
            guard customerCategory != value else { return }
            customerCategory = value
            travelAgencyCode = ""
            travelAgencyName = ""
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(LocalizedStringKey(subtitle))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.55))
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.09) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.18), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func openSystemURL(_ rawValue: String) {
        guard let url = URL(string: rawValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rawValue) else { return }
        openURL(url)
    }

    private func addContact() {
        contacts.append(ContactDraft(type: "电话", value: "", isDefault: contacts.isEmpty))
    }

    private func setDefaultContact(_ id: UUID) {
        for index in contacts.indices { contacts[index].isDefault = contacts[index].id == id }
    }

    private func removeContact(_ id: UUID) {
        withAnimation { contacts.removeAll { $0.id == id } }
        if !contacts.isEmpty, !contacts.contains(where: { $0.isDefault }) {
            contacts[0].isDefault = true
        }
    }

    private func addAddress() {
        addresses.append(AddressDraft(type: "家", value: "", isDefault: addresses.isEmpty))
    }

    private func setDefaultAddress(_ id: UUID) {
        for index in addresses.indices { addresses[index].isDefault = addresses[index].id == id }
    }

    private func removeAddress(_ id: UUID) {
        withAnimation { addresses.removeAll { $0.id == id } }
        if !addresses.isEmpty, !addresses.contains(where: { $0.isDefault }) {
            addresses[0].isDefault = true
        }
    }

    private func saveCustomer() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { message = "请输入客户名称"; return }

        let record: Custumer
        if let customerID = registryCustomerID, let ownerScope = registryOwnerScope {
            guard DataOwnership.activeScope == ownerScope else {
                message = String(localized: "账号已切换，请返回当前账号后重新打开客户资料。", locale: AppLanguageSettings.currentLocale)
                return
            }
            let conflictKey = "\(ownerScope)|customers|\(customerID.lowercased())"
            let conflictDescriptor = FetchDescriptor<CloudSyncConflict>(predicate: #Predicate {
                $0.key == conflictKey && $0.ownerScope == ownerScope
            })
            do {
                if let conflict = try modelContext.fetch(conflictDescriptor).first, conflict.isRemoteDeletion {
                    message = String(localized: "此客户已在另一台设备删除。请先处理同步冲突，当前修改未保存。", locale: AppLanguageSettings.currentLocale)
                    return
                }
            } catch {
                message = String(localized: "无法确认客户的同步状态，修改尚未保存。请稍后重试。", locale: AppLanguageSettings.currentLocale)
                return
            }
            let descriptor = FetchDescriptor<Custumer>(predicate: #Predicate {
                $0.uuid == customerID && $0.ownerScope == ownerScope
            })
            do {
                if let current = try modelContext.fetch(descriptor).first {
                    record = current
                } else {
                    message = String(localized: "此客户已在另一台设备删除，当前修改未保存。请先处理同步冲突。", locale: AppLanguageSettings.currentLocale)
                    return
                }
            } catch {
                message = String(localized: "客户资料读取失败，修改尚未保存。请返回后重试。", locale: AppLanguageSettings.currentLocale)
                return
            }
        } else {
            record = Custumer(name: trimmedName, email: "", csource: "客户", type: 1, customerCategory: customerCategory)
            modelContext.insert(record)
        }
        record.name = trimmedName
        record.customerCategory = customerCategory
        record.travelAgencyCode = customerCategory == 2 ? travelAgencyCode : ""
        record.travelAgencyName = customerCategory == 2 ? travelAgencyName : ""
        record.languagePreference = languagePreference
        record.remark = String(remark.prefix(256))
        record.updateAt = Date()
        record.email = contacts.first(where: { $0.type == "邮箱" })?.value ?? ""
        if let avatarData {
            do {
                let folder = Self.avatarFolder
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let fileName = "\(record.uuid).image"
                try avatarData.write(to: folder.appendingPathComponent(fileName), options: .atomic)
                record.avatarUrl = "CustomerAvatars/\(fileName)"
            } catch {
                message = "照片保存失败"
                return
            }
        }

        let oldContacts = record.connecttype
        for old in oldContacts { modelContext.delete(old) }
        var contactsToSave = contacts.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !contactsToSave.isEmpty {
            let selected = contactsToSave.firstIndex(where: { $0.isDefault }) ?? 0
            for index in contactsToSave.indices { contactsToSave[index].isDefault = index == selected }
        }
        for draft in contactsToSave {
            modelContext.insert(Connect(connectlable: draft.type, connecttype: draft.value.trimmingCharacters(in: .whitespacesAndNewlines), isDefault: draft.isDefault, customer: record))
        }
        let oldAddresses = record.addresses
        for old in oldAddresses { modelContext.delete(old) }
        var addressesToSave = addresses.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !addressesToSave.isEmpty {
            let selected = addressesToSave.firstIndex(where: { $0.isDefault }) ?? 0
            for index in addressesToSave.indices { addressesToSave[index].isDefault = index == selected }
        }
        for draft in addressesToSave {
            modelContext.insert(Address(addlable: draft.type, addresses: draft.value.trimmingCharacters(in: .whitespacesAndNewlines), isDefault: draft.isDefault, customer: record))
        }
        do { try modelContext.save(); dismiss() }
        catch { message = error.localizedDescription }
    }

    private static var avatarFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CustomerAvatars", isDirectory: true)
    }

    private static func loadAvatar(_ path: String) -> Data? {
        guard !path.isEmpty else { return nil }
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) :
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(path)
        return try? Data(contentsOf: url)
    }
}

private struct ContactDraft: Identifiable {
    let id = UUID()
    var type: String
    var value: String
    var isDefault: Bool = false
}

private struct AddressDraft: Identifiable {
    let id = UUID()
    var type: String
    var value: String
    var isDefault: Bool = false
}

struct AddressSuggestionField: View {
    @Binding var text: String
    @ObservedObject var searcher: AddressAutocompleteSearcher
    @FocusState private var isFocused: Bool
    var placeholder = "输入地址，可搜索地点"
    let isActive: Bool
    let onFocus: () -> Void
    let onSelect: (String) -> Void

    init(
        text: Binding<String>,
        searcher: AddressAutocompleteSearcher,
        placeholder: String = "输入地址，可搜索地点",
        isActive: Bool,
        onFocus: @escaping () -> Void,
        onSelect: @escaping (String) -> Void
    ) {
        _text = text
        self.searcher = searcher
        self.placeholder = placeholder
        self.isActive = isActive
        self.onFocus = onFocus
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .focused($isFocused)
                .keyboardDoneToolbar()
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .onChange(of: text) { _, value in
                    searcher.searchQuery = value
                    onFocus()
                }
            if isActive && !searcher.completions.isEmpty {
                ForEach(Array(searcher.completions.prefix(5)), id: \.self) { completion in
                    Button {
                        let value = [completion.title, completion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                        onSelect(value)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(completion.title).foregroundStyle(.primary)
                            if !completion.subtitle.isEmpty { Text(completion.subtitle).font(.caption).foregroundStyle(.secondary) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    @Previewable @State var dataSource = DataSource()
    @Previewable @State var auth = AuthViewModel()

    ContentView()
        .environment(dataSource)
        .environment(auth)
        .modelContainer(for: AppDataSchema.modelTypes, inMemory: true)
}
