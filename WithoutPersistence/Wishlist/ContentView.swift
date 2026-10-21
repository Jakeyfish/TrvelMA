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

    var body: some View {
        Group{
            TabView {
                Tab("主页", systemImage: "house.fill") {
                    WishlistView()
                    
                }
                
                Tab("行程", systemImage: "books.vertical") {
                    TripsPageView()
                }
                Tab("名片", systemImage: "person.text.rectangle.fill") {
                    BusinessCardView()
                }
                Tab("钱包", systemImage: "wallet.bifold.fill") {
                    WalletView()
                }
                Tab("客户", systemImage: "person.crop.rectangle.badge.plus.fill") {
                    CustomerListView()
                }
                
                //            Tab(role: .search) {
                //                SearchView()
                //            }
            }
        }
    }
}


struct CustomerListView: View {
    @Environment(\.locale) private var locale
    @Query private var customers: [Custumer]
    @Query private var tripBookings: [TripBookingRecord]
    @AppStorage(BaseCurrencyCatalog.countryCodeKey) private var baseCurrencyCountry = BaseCurrencyCatalog.defaultCountryCode
    @State private var isAddingCustomer = false
    @State private var selectedFilter: CustomerListFilter = .all
    @State private var searchText = ""

    init() {
        let scope = DataOwnership.activeScope
        _customers = Query(filter: #Predicate { $0.ownerScope == scope })
        _tripBookings = Query(filter: #Predicate { $0.ownerScope == scope })
    }

    private var sortedCustomers: [Custumer] {
        customers.sorted { $0.updateAt > $1.updateAt }
    }

    private var tripCountsByCustomerID: [String: Int] {
        let customersByName = Dictionary(grouping: customers, by: { $0.name })
        var counts: [String: Int] = [:]
        for booking in tripBookings where !booking.isCancelled {
            if let customerID = booking.customerUUID {
                counts[customerID, default: 0] += 1
            } else if let matches = customersByName[booking.customerName], matches.count == 1,
                      let customerID = matches.first?.uuid {
                counts[customerID, default: 0] += 1
            }
        }
        return counts
    }

    private var customerContributionTrips: [TripBookingRecord] {
        var seen = Set<UUID>()
        return customers
            .flatMap { customerTripRecords(for: $0, customers: customers, bookings: tripBookings) }
            .filter { seen.insert($0.id).inserted }
    }

    private var customerContributionTotalIncome: Double {
        customerContributionTrips.reduce(0) { $0 + netIncome(for: $1) }
    }

    private var customerContributionUnpaid: Double {
        customerContributionTrips
            .filter { !$0.isPaid }
            .reduce(0) { $0 + max(0, netIncome(for: $1)) }
    }

    private func netIncome(for booking: TripBookingRecord) -> Double {
        booking.price + booking.tip + booking.expenseAdjustments.reduce(0) { total, item in
            total + (item.isAddition ? abs(item.amount) : -abs(item.amount))
        }
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 10) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .accessibilityHidden(true)

                        Text("客户")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Button {
                        isAddingCustomer = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新增客户")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

                VStack(spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        customerStatCard(icon: "person.2.fill", title: "客户", value: "\(customers.count)", detail: "\(customers.count)/1000 位客户", tint: .teal)
                        customerContributionCard
                    }

                    HStack(spacing: 10) {
                        ForEach(CustomerListFilter.allCases) { filter in
                            Button {
                                selectedFilter = filter
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: filter.icon)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(selectedFilter == filter ? Color.accentColor : Color.secondary)
                                        Text(LocalizedStringKey(filter.title))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                                .padding(.horizontal, 10)
                                .background(selectedFilter == filter ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(selectedFilter == filter ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.15), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 29, height: 29)
                            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .accessibilityHidden(true)
                        SystemIMETextField(
                            text: $searchText,
                            placeholder: String(localized: "搜索姓名、电话、邮箱、地址或备注", locale: locale),
                            capitalization: .none
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .fixedSize(horizontal: false, vertical: true)
                        if !searchText.isEmpty {
                            Button {
                                withAnimation(.easeOut(duration: 0.15)) { searchText = "" }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, height: 30)
                                    .background(Color(.tertiarySystemGroupedBackground), in: Circle())
                            }
                            .accessibilityLabel("清除搜索")
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(searchText.isEmpty ? Color.secondary.opacity(0.13) : Color.accentColor.opacity(0.42), lineWidth: 1))

                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredCustomers, id: \.uuid) { customer in
                            NavigationLink {
                                CustomerBrowseView(customer: customer)
                            } label: {
                                CustomerCardView(customer: customer, tripCount: tripCountsByCustomerID[customer.uuid] ?? 0)
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
            .sheet(isPresented: $isAddingCustomer) {
                NavigationStack {
                    CustomerDetailView(customer: nil)
                }
            }
        }
        .font(.system(size: 15))
    }

    private func customerStatCard(icon: String, title: String, value: String, detail: LocalizedStringKey, tint: Color, highlightValue: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 27, height: 27)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                Text(LocalizedStringKey(title))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(highlightValue ? Color.green : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private var customerContributionCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .frame(width: 27, height: 27)
                    .background(Color.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                Text("客户贡献")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 4) {
                Text("总收入")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 4)
                Text(BaseCurrencyCatalog.format(customerContributionTotalIncome, countryCode: baseCurrencyCountry))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
            HStack(spacing: 4) {
                Text("未收款")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 4)
                Text(BaseCurrencyCatalog.format(customerContributionUnpaid, countryCode: baseCurrencyCountry))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
}

private enum CustomerListFilter: String, CaseIterable, Identifiable {
    case all, regular, agency

    var id: Self { self }
    var title: String {
        switch self {
        case .all: "全部"
        case .regular: "个人客户筛选"
        case .agency: "旅行社"
        }
    }
    var icon: String {
        switch self {
        case .all: "person.2.fill"
        case .regular: "person.fill"
        case .agency: "building.2.fill"
        }
    }
}

private struct CustomerCardView: View {
    let customer: Custumer
    let tripCount: Int

    var body: some View {
        HStack(spacing: 14) {
            CustomerAvatarView(path: customer.avatarUrl, size: 48, fallbackName: customer.name)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(customer.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(customer.customerCategory == 2 ? "旅行社" : "普通客户")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(customer.customerCategory == 2 ? .orange : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((customer.customerCategory == 2 ? Color.orange : Color.secondary).opacity(0.12), in: Capsule())
                }

                if let phone = customer.connecttype.first?.connecttype, !phone.isEmpty {
                    Label(phone, systemImage: "phone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if !customer.email.isEmpty {
                    Label(customer.email, systemImage: "envelope")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(spacing: 4) {
                Image(systemName: "car.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("\(tripCount) 次出行")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private var hasPendingRemoteDeletion: Bool {
        syncConflicts.contains {
            $0.recordID.caseInsensitiveCompare(customer.id) == .orderedSame && $0.isRemoteDeletion
        }
    }

    private var customerTrips: [TripBookingRecord] {
        let isUniqueCustomerName = allCustomers.filter { $0.name == customer.name }.count == 1
        return tripBookings
            .filter { booking in
                guard !booking.isCancelled else { return false }
                if booking.customerUUID == customer.id { return true }
                return booking.customerUUID == nil
                    && isUniqueCustomerName
                    && booking.customerName == customer.name
            }
            .sorted { $0.appointmentDate > $1.appointmentDate }
    }

    private var hasAnyTripHistory: Bool {
        let isUniqueCustomerName = allCustomers.filter { $0.name == customer.name }.count == 1
        return tripBookings.contains { booking in
            if booking.customerUUID == customer.id { return true }
            return booking.customerUUID == nil
                && isUniqueCustomerName
                && booking.customerName == customer.name
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    CustomerAvatarView(path: customer.avatarUrl, size: 76, fallbackName: customer.name)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(customer.name).font(.headline.weight(.semibold))
                        Text(customer.customerCategory == 2 ? "旅行社" : "普通客户")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("语言喜好", value: AppLanguage(rawValue: customer.languagePreference)?.nativeName ?? customer.languagePreference)
                if customer.customerCategory == 2 {
                    HStack(spacing: 12) {
                        compactCustomerValue("旅行社代码", customer.travelAgencyCode.isEmpty ? "未选择" : customer.travelAgencyCode)
                        compactCustomerValue("旅行社名称", customer.travelAgencyName.isEmpty ? "未选择" : customer.travelAgencyName)
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
                ForEach(customer.contacts) { contact in
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
                if customer.contacts.isEmpty && customer.email.isEmpty {
                    Text("暂无联系方式").foregroundStyle(.secondary)
                } else if customer.contacts.isEmpty {
                    HStack {
                        Text("邮箱")
                        Spacer()
                        Text(customer.email).foregroundStyle(.secondary)
                    }
                }
            }

            Section("常用地址") {
                ForEach(customer.addresses) { address in
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
                if customer.addresses.isEmpty { Text("暂无常用地址").foregroundStyle(.secondary) }
            }

            Section("备注") {
                Text(customer.remark.isEmpty ? "暂无备注" : customer.remark)
                    .foregroundStyle(customer.remark.isEmpty ? .secondary : .primary)
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
                        CustomerDetailView(profile: customer)
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
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(String(fallbackName.prefix(1)))
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
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
                    .frame(minHeight: 100)
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
                message = "账号已切换，请返回当前账号后重新打开客户资料。"
                return
            }
            let conflictKey = "\(ownerScope)|customers|\(customerID.lowercased())"
            let conflictDescriptor = FetchDescriptor<CloudSyncConflict>(predicate: #Predicate {
                $0.key == conflictKey && $0.ownerScope == ownerScope
            })
            do {
                if let conflict = try modelContext.fetch(conflictDescriptor).first, conflict.isRemoteDeletion {
                    message = "此客户已在另一台设备删除。请先处理同步冲突，当前修改未保存。"
                    return
                }
            } catch {
                message = "无法确认客户的同步状态，修改尚未保存。请稍后重试。"
                return
            }
            let descriptor = FetchDescriptor<Custumer>(predicate: #Predicate {
                $0.uuid == customerID && $0.ownerScope == ownerScope
            })
            do {
                if let current = try modelContext.fetch(descriptor).first {
                    record = current
                } else {
                    message = "此客户已在另一台设备删除，当前修改未保存。请先处理同步冲突。"
                    return
                }
            } catch {
                message = "客户资料读取失败，修改尚未保存。请返回后重试。"
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

private struct AddressSuggestionField: View {
    @Binding var text: String
    @ObservedObject var searcher: AddressAutocompleteSearcher
    let isActive: Bool
    let onFocus: () -> Void
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SystemIMETextField(text: $text, placeholder: "输入地址，可搜索地点")
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
