import SwiftUI
import PhotosUI
import UIKit

struct CloudCustomerDirectoryView: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var directory = CloudCustomerDirectoryModel()
    @State private var searchText = ""
    @State private var selectedFilter: CustomerListFilter = .all
    @State private var isAddingCustomer = false

    private var visibleCustomers: [CloudOnlineRepository.CustomerRecord] {
        directory.customers.filter { customer in
            let matchesFilter = switch selectedFilter {
            case .all: true
            case .regular: customer.category == 1
            case .agency: customer.category == 2
            }
            guard matchesFilter else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            let categoryName = customer.category == 2 ? "旅行社" : "普通客户"
            let searchable = [customer.name, customer.email, customer.source, customer.remark,
                              customer.languagePreference, categoryName, String(customer.type)]
                + customer.contacts.flatMap { [$0.label, $0.contactType] }
                + customer.addresses.flatMap { [$0.label, $0.address] }
            return searchable.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CustomerDirectoryControls(
                    resultCount: visibleCustomers.count,
                    selectedFilter: $selectedFilter,
                    searchText: $searchText,
                    onAdd: { isAddingCustomer = true },
                    isAddDisabled: directory.isLoading
                )
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if directory.isLoading && directory.customers.isEmpty {
                            ProgressView().padding(.top, 32)
                        } else if let error = directory.errorMessage, directory.customers.isEmpty {
                            ContentUnavailableView {
                                Label("无法载入客户", systemImage: "icloud.slash")
                            } description: {
                                Text(error)
                            } actions: {
                                Button("重试") { Task { await directory.reload(using: auth) } }
                                    .buttonStyle(.borderedProminent)
                            }
                            .padding(.top, 24)
                        } else {
                            ForEach(visibleCustomers) { customer in
                                NavigationLink {
                                    CloudCustomerDetailView(customer: customer, directory: directory)
                                } label: {
                                    CustomerDirectoryRow(
                                        name: customer.name,
                                        category: customer.category
                                    ) {
                                        OnlineCustomerAvatar(customer: customer, directory: directory, size: 48)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            if visibleCustomers.isEmpty {
                                ContentUnavailableView(searchText.isEmpty ? "暂无客户" : "没有找到客户",
                                                       systemImage: searchText.isEmpty ? "person.crop.rectangle" : "magnifyingglass")
                                    .padding(.top, 24)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await directory.reload(using: auth) }
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .adaptiveFormPresentation(isPresented: $isAddingCustomer) {
                NavigationStack {
                    CloudCustomerEditor(directory: directory, customer: nil)
                }
            }
            .task(id: "\(auth.isCloudAccount)|\(auth.currentEmail)") {
                directory.clearForAccountChange()
                await directory.reload(using: auth)
            }
            .alert("无法更新客户目录", isPresented: Binding(
                get: { directory.errorMessage != nil && !directory.customers.isEmpty },
                set: { if !$0 { directory.clearError() } }
            )) {
                Button("确定", role: .cancel) { directory.clearError() }
            } message: {
                Text(directory.errorMessage ?? "")
            }
        }
        .font(.system(size: 15))
    }
}

private struct CloudCustomerDetailView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(NavigationProvider.defaultsKey) private var defaultNavigationProvider = NavigationProvider.appleMaps.rawValue
    let customer: CloudOnlineRepository.CustomerRecord
    let directory: CloudCustomerDirectoryModel
    @State private var isConfirmingDelete = false
    @State private var isShowingDeleteBlockAlert = false
    @State private var hasLoadedTrips = false

    private var currentCustomer: CloudOnlineRepository.CustomerRecord {
        directory.customers.first(where: { $0.id == customer.id }) ?? customer
    }

    private var trips: [CloudOnlineRepository.CustomerTripRecord] {
        directory.tripsByCustomerID[customer.id] ?? []
    }

    private var displayedTrips: [CloudOnlineRepository.CustomerTripRecord] {
        trips.filter { !$0.isCancelled }
    }

    private var hasAnyTripHistory: Bool { !trips.isEmpty }

    var body: some View {
        List {
            headerSection
            contactsSection
            addressesSection
            remarksSection
            tripHistorySection
        }
        .task(id: customer.id) {
            hasLoadedTrips = false
            await directory.reloadTrips(for: customer.id, using: auth)
            hasLoadedTrips = directory.tripErrorByCustomerID[customer.id] == nil
        }
        .navigationTitle("客户资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CloudCustomerEditor(directory: directory, customer: currentCustomer)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    guard hasLoadedTrips else { return }
                    if hasAnyTripHistory { isShowingDeleteBlockAlert = true }
                    else { isConfirmingDelete = true }
                } label: { Image(systemName: "trash") }
                    .accessibilityLabel("删除客户")
                    .disabled(!hasLoadedTrips || directory.loadingTripCustomerIDs.contains(customer.id))
            }
        }
        .confirmationDialog("确定删除该客户？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    if await directory.delete(id: customer.id, using: auth) { dismiss() }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("无法删除客户", isPresented: Binding(
            get: { directory.errorMessage != nil },
            set: { if !$0 { directory.clearError() } }
        )) {
            Button("确定", role: .cancel) { directory.clearError() }
        } message: {
            Text(directory.errorMessage ?? "")
        }
        .alert("提示", isPresented: $isShowingDeleteBlockAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text("该客户已有出行记录，不能删除。")
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                OnlineCustomerAvatar(customer: currentCustomer, directory: directory, size: 76)
                VStack(alignment: .leading, spacing: 6) {
                    Text(currentCustomer.name).font(.headline.weight(.semibold))
                    Text(currentCustomer.category == 2 ? "旅行社" : "普通客户").font(.footnote).foregroundStyle(.secondary)
                }
            }
            LabeledContent("语言喜好", value: AppLanguage(rawValue: currentCustomer.languagePreference)?.nativeName ?? currentCustomer.languagePreference)
            if currentCustomer.category == 2 {
                HStack(spacing: 12) {
                    detailValue("旅行社代码", currentCustomer.travelAgencyCode.isEmpty ? "未选择" : currentCustomer.travelAgencyCode)
                    detailValue("旅行社名称", currentCustomer.travelAgencyName.isEmpty ? "未选择" : currentCustomer.travelAgencyName)
                }
            }
        }
    }

    private var contactsSection: some View {
        Section("联系方式") {
            if currentCustomer.contacts.isEmpty && currentCustomer.email.isEmpty {
                Text("暂无联系方式").foregroundStyle(.secondary)
            } else {
                ForEach(currentCustomer.contacts) { contact in
                    contactRow(contact)
                }
                if currentCustomer.contacts.isEmpty, !currentCustomer.email.isEmpty {
                    LabeledContent("邮箱", value: currentCustomer.email)
                }
            }
        }
    }

    private func contactRow(_ contact: CloudOnlineRepository.ContactRecord) -> some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(contact.label.isEmpty ? contact.contactType : contact.label))
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            if contact.isDefault {
                Text("默认").font(.system(size: 10, weight: .medium)).foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6).padding(.vertical, 3).background(Color.accentColor.opacity(0.10), in: Capsule())
            }
            Text(contact.value).font(.subheadline).lineLimit(1).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            contactActions(for: contact)
        }
        .font(.system(size: 12)).padding(.vertical, 3)
    }

    private var addressesSection: some View {
        Section("常用地址") {
            if currentCustomer.addresses.isEmpty {
                Text("暂无常用地址").foregroundStyle(.secondary)
            } else {
                ForEach(currentCustomer.addresses) { address in
                    addressRow(address)
                }
            }
        }
    }

    private func addressRow(_ address: CloudOnlineRepository.AddressRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(LocalizedStringKey(address.label)).font(.footnote.weight(.medium))
                if address.isDefault { Text("默认").font(.system(size: 11)).foregroundStyle(Color.accentColor) }
            }
            Button { openMap(address.address) } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text(address.address).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                    Label("使用默认导航", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 12)).foregroundStyle(Color.accentColor)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.padding(.vertical, 4)
    }

    @ViewBuilder
    private var tripHistorySection: some View {
        Section {
            if directory.loadingTripCustomerIDs.contains(customer.id) && trips.isEmpty {
                ProgressView()
            } else if let tripError = directory.tripErrorByCustomerID[customer.id] {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tripError).font(.footnote).foregroundStyle(.secondary)
                    Button("重试") {
                        Task {
                            hasLoadedTrips = false
                            await directory.reloadTrips(for: customer.id, using: auth)
                            hasLoadedTrips = directory.tripErrorByCustomerID[customer.id] == nil
                        }
                    }
                }
            } else if displayedTrips.isEmpty {
                Text("暂无出行记录").foregroundStyle(.secondary)
            } else {
                ForEach(displayedTrips) { trip in
                    customerTripRow(trip)
                }
            }
        } header: { Text("出行记录") }
    }

    private func customerTripRow(_ trip: CloudOnlineRepository.CustomerTripRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            customerTripValue("出行日期", value: trip.appointmentDate.customerDisplayDate)
                .frame(maxWidth: .infinity, alignment: .leading)
            customerTripValue("目的地", value: trip.locationEnd.isEmpty ? "未填写" : trip.locationEnd)
                .frame(maxWidth: .infinity, alignment: .leading)
            customerTripValue("车费", value: formatCustomerCurrency(trip.price, code: directory.currencyCode))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(.vertical, 3).font(.system(size: 11))
    }

    private func detailValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
    }

    private var remarksSection: some View {
        Section("备注") {
            if currentCustomer.remark.isEmpty {
                Text("暂无备注").foregroundStyle(.secondary)
            } else {
                Text(currentCustomer.remark).foregroundStyle(.primary)
            }
        }
    }

    @ViewBuilder
    private func contactActions(for contact: CloudOnlineRepository.ContactRecord) -> some View {
        let type = contact.contactType.lowercased()
        if contact.contactType == "电话" || type.contains("phone") {
            Button { openContactURL("tel://\(contact.value)") } label: { Image(systemName: "phone.fill") }.accessibilityLabel("拨打电话")
            Button { openContactURL("sms:\(contact.value)") } label: { Image(systemName: "message.fill") }.accessibilityLabel("发送信息")
        } else if contact.contactType == "邮箱" || type.contains("email") {
            Button { openContactURL("mailto:\(contact.value)") } label: { Image(systemName: "envelope.fill") }.accessibilityLabel("发送邮件")
        }
    }

    private func customerTripValue(_ title: String, value: String) -> some View {
        VStack(alignment: title == "车费" ? .trailing : .leading, spacing: 4) {
            Text(LocalizedStringKey(title)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
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
}

@MainActor
private struct CloudCustomerEditor: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let directory: CloudCustomerDirectoryModel
    let customer: CloudOnlineRepository.CustomerRecord?

    @State private var name: String
    @State private var category: Int
    @State private var agencyCode: String
    @State private var agencyName: String
    @State private var languagePreference: String
    @State private var remark: String
    @State private var contacts: [OnlineContactDraft]
    @State private var addresses: [OnlineAddressDraft]
    @State private var isShowingAgencyPicker = false
    @State private var addressSearchTarget: UUID?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarData: Data?
    @StateObject private var addressSearcher = AddressAutocompleteSearcher()

    private let contactTypes = ["电话", "微信", "邮箱", "WhatsApp", "LINE"]
    private let addressTypes = ["家", "公司", "其他"]

    init(directory: CloudCustomerDirectoryModel, customer: CloudOnlineRepository.CustomerRecord?) {
        self.directory = directory
        self.customer = customer
        _name = State(initialValue: customer?.name ?? "")
        _category = State(initialValue: customer?.category ?? 1)
        _agencyCode = State(initialValue: customer?.travelAgencyCode ?? "")
        _agencyName = State(initialValue: customer?.travelAgencyName ?? "")
        _languagePreference = State(initialValue: customer?.languagePreference ?? "zh-Hans")
        _remark = State(initialValue: customer?.remark ?? "")
        var savedContacts = customer?.contacts.map(OnlineContactDraft.init) ?? []
        if savedContacts.isEmpty, let email = customer?.email, !email.isEmpty {
            savedContacts = [OnlineContactDraft(type: "邮箱", value: email, isDefault: true)]
        }
        if !savedContacts.isEmpty, !savedContacts.contains(where: \.isDefault) { savedContacts[0].isDefault = true }
        if let selected = savedContacts.firstIndex(where: \.isDefault) {
            for index in savedContacts.indices { savedContacts[index].isDefault = index == selected }
        }
        var savedAddresses = customer?.addresses.map(OnlineAddressDraft.init) ?? []
        if !savedAddresses.isEmpty, !savedAddresses.contains(where: \.isDefault) { savedAddresses[0].isDefault = true }
        if let selected = savedAddresses.firstIndex(where: \.isDefault) {
            for index in savedAddresses.indices { savedAddresses[index].isDefault = index == selected }
        }
        _contacts = State(initialValue: savedContacts)
        _addresses = State(initialValue: savedAddresses)
    }

    var body: some View {
        let selectedAvatarData = avatarData
        let displayName = name
        let hasExistingAvatar = !(customer?.avatarURL.isEmpty ?? true)
        return Form {
            Section {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    VStack(spacing: 8) {
                        ZStack(alignment: .bottomTrailing) {
                            Group {
                                if let selectedAvatarData, let image = UIImage(data: selectedAvatarData) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                } else if hasExistingAvatar {
                                    OnlineCustomerAvatar(customer: customer, directory: directory, size: 88, fallbackName: displayName)
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                        .foregroundStyle(Color.accentColor.opacity(0.65))
                                }
                            }
                            .frame(width: 88, height: 88)
                            .clipped()
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.accentColor.opacity(0.2), lineWidth: 1))

                            Image(systemName: "camera.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(9)
                                .background(Color.accentColor, in: Circle())
                                .overlay(Circle().stroke(Color(.systemGroupedBackground), lineWidth: 2))
                        }
                        Label(selectedAvatarData == nil && !hasExistingAvatar ? "添加照片" : "更换照片", systemImage: "camera")
                            .font(.footnote)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            Section("基本信息") {
                TextField("客户名称", text: $name)
                VStack(alignment: .leading, spacing: 10) {
                    Text("客户类型").foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        customerTypeOption("普通客户", subtitle: "个人与家庭出行", icon: "person.fill", value: 1)
                        customerTypeOption("旅行社", subtitle: "团队与机构订单", icon: "building.2.fill", value: 2)
                    }
                }
                Picker("语言喜好", selection: $languagePreference) {
                    ForEach(AppLanguage.options) { language in
                        Text(language.nativeName).tag(language.rawValue)
                    }
                }
            }
            if category == 2 {
                Section("旅行社信息") {
                    Button { isShowingAgencyPicker = true } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text("旅行社代码")
                                Spacer()
                                Text(agencyCode.isEmpty ? "点击选择" : agencyCode)
                                    .foregroundStyle(agencyCode.isEmpty ? Color.accentColor : Color.secondary)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            HStack {
                                Text("旅行社名称")
                                Spacer()
                                Text(agencyName.isEmpty ? "点击选择" : agencyName)
                                    .foregroundStyle(agencyName.isEmpty ? Color.accentColor : Color.secondary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            Section("联系方式") {
                ForEach($contacts) { $contact in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Menu {
                                ForEach(contactTypes, id: \.self) { type in
                                    Button { contact.type = type } label: {
                                        if contact.type == type { Label(LocalizedStringKey(type), systemImage: "checkmark") }
                                        else { Text(LocalizedStringKey(type)) }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(LocalizedStringKey(contact.type))
                                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                                }.foregroundStyle(Color.accentColor).fixedSize()
                            }
                            SystemIMETextField(
                                text: $contact.value,
                                placeholder: "输入联系方式",
                                keyboardType: contact.type == "电话" ? .phonePad : (contact.type == "邮箱" ? .emailAddress : .default),
                                capitalization: contact.type == "邮箱" ? .none : .sentences,
                                autocorrection: contact.type == "邮箱" ? .no : .default,
                                textContentType: contact.type == "电话" ? .telephoneNumber : (contact.type == "邮箱" ? .emailAddress : nil)
                            )
                        }
                        HStack(spacing: 12) {
                            Button { setDefaultContact(contact.id) } label: {
                                Label("默认", systemImage: contact.isDefault ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 12)).foregroundStyle(contact.isDefault ? Color.accentColor : Color.secondary)
                            }.buttonStyle(.plain)
                            Spacer()
                            Button(role: .destructive) { removeContact(contact.id) } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(.red)
                            }.buttonStyle(.plain).accessibilityLabel("删除联系方式")
                        }
                    }
                }
                Button { contacts.append(OnlineContactDraft(isDefault: contacts.isEmpty)) } label: {
                    Label("增加联系方式", systemImage: "plus")
                }
            }
            Section("常用地址") {
                ForEach($addresses) { $address in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Menu {
                                ForEach(addressTypes, id: \.self) { type in
                                    Button { address.label = type } label: {
                                        if address.label == type { Label(LocalizedStringKey(type), systemImage: "checkmark") }
                                        else { Text(LocalizedStringKey(type)) }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(LocalizedStringKey(address.label))
                                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                                }.foregroundStyle(Color.accentColor).fixedSize()
                            }
                            AddressSuggestionField(
                                text: $address.value,
                                searcher: addressSearcher,
                                isActive: addressSearchTarget == address.id,
                                onFocus: { addressSearchTarget = address.id },
                                onSelect: { selected in
                                    address.value = selected
                                    addressSearcher.searchQuery = ""
                                    addressSearchTarget = nil
                                }
                            ).layoutPriority(1)
                        }
                        HStack(spacing: 12) {
                            Button { setDefaultAddress(address.id) } label: {
                                Label("默认", systemImage: address.isDefault ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 12)).foregroundStyle(address.isDefault ? Color.accentColor : Color.secondary)
                            }.buttonStyle(.plain)
                            Spacer()
                            Button(role: .destructive) { removeAddress(address.id) } label: {
                                Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundStyle(.red)
                            }.buttonStyle(.plain).accessibilityLabel("删除常用地址")
                        }
                    }
                }
                Button { addresses.append(OnlineAddressDraft(isDefault: addresses.isEmpty)) } label: {
                    Label("增加常用地址", systemImage: "plus")
                }
            }
            Section("备注（最多 256 字）") {
                LimitedIMETextEditor(text: $remark, maxLength: 256)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 100)
                Text("\(remark.count)/256")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .navigationTitle(customer == nil ? "新增客户" : "编辑客户")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { Task { await save() } }
                    .disabled(directory.isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .overlay {
            if directory.isSaving { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) }
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            avatarData = try? await selectedPhoto.loadTransferable(type: Data.self)
        }
        .sheet(isPresented: $isShowingAgencyPicker) {
            CloudTravelAgencySelectionView(agencies: directory.agencies) { agency in
                agencyCode = agency.agencyCode
                agencyName = agency.name
            }
        }
        .onChange(of: category) { _, value in
            if value != 2 { agencyCode = ""; agencyName = "" }
        }
        .onChange(of: agencyCode) { _, code in
            guard let agency = directory.agencies.first(where: { $0.agencyCode == code }) else { return }
            agencyName = agency.name
        }
        .alert("无法保存客户", isPresented: Binding(
            get: { directory.errorMessage != nil },
            set: { if !$0 { directory.clearError() } }
        )) {
            Button("确定", role: .cancel) { directory.clearError() }
        } message: {
            Text(directory.errorMessage ?? "")
        }
    }

    private func setDefaultContact(_ id: UUID) {
        for index in contacts.indices { contacts[index].isDefault = contacts[index].id == id }
    }

    private func removeContact(_ id: UUID) {
        withAnimation { contacts.removeAll { $0.id == id } }
        if !contacts.isEmpty, !contacts.contains(where: \.isDefault) { contacts[0].isDefault = true }
    }

    private func customerTypeOption(_ title: String, subtitle: String, icon: String, value: Int) -> some View {
        let selected = category == value
        return Button { category = value } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(selected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(title)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                    Text(LocalizedStringKey(subtitle)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.55))
            }
            .padding(10).frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.09) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(selected ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func setDefaultAddress(_ id: UUID) {
        for index in addresses.indices { addresses[index].isDefault = addresses[index].id == id }
    }

    private func removeAddress(_ id: UUID) {
        withAnimation { addresses.removeAll { $0.id == id } }
        if !addresses.isEmpty, !addresses.contains(where: \.isDefault) { addresses[0].isDefault = true }
    }

    private func save() async {
        let id = customer?.id ?? UUID().uuidString.lowercased()
        let savedContacts = contacts.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let savedAddresses = addresses.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let defaultContactID = savedContacts.first(where: \.isDefault)?.id ?? savedContacts.first?.id
        let dto = CloudOnlineRepository.CustomerWrite(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: savedContacts.first(where: { $0.type.localizedCaseInsensitiveContains("邮箱") })?.value ?? customer?.email ?? "",
            avatarURL: customer?.avatarURL ?? "",
            source: customer?.source ?? "客户",
            type: customer?.type ?? 1,
            category: category,
            travelAgencyCode: category == 2 ? agencyCode : "",
            travelAgencyName: category == 2 ? agencyName : "",
            languagePreference: languagePreference,
            remark: String(remark.prefix(256)),
            createdAt: .now
        )
        let contactDTOs = savedContacts.map {
            CloudOnlineRepository.ContactWrite(
                id: $0.remoteID ?? UUID().uuidString.lowercased(),
                label: $0.type,
                contactType: $0.type,
                value: $0.value.trimmingCharacters(in: .whitespacesAndNewlines),
                isDefault: $0.id == defaultContactID
            )
        }
        let addressDTOs = savedAddresses.map {
            CloudOnlineRepository.AddressWrite(
                id: $0.remoteID ?? UUID().uuidString.lowercased(),
                label: $0.label,
                address: $0.value.trimmingCharacters(in: .whitespacesAndNewlines),
                isDefault: $0.isDefault
            )
        }
        if await directory.save(customer: dto, contacts: contactDTOs, addresses: addressDTOs,
                                avatarData: avatarData, using: auth) {
            dismiss()
        }
    }
}

private struct CloudTravelAgencySelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let agencies: [CloudOnlineRepository.TravelAgencyRecord]
    let onSelect: (CloudOnlineRepository.TravelAgencyRecord) -> Void
    @State private var searchText = ""

    private var matches: [CloudOnlineRepository.TravelAgencyRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return agencies.filter {
            query.isEmpty || [$0.agencyCode, $0.name, $0.contactPerson, $0.phone]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if matches.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "暂无合作旅行社" : "没有找到旅行社",
                        systemImage: searchText.isEmpty ? "building.2" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "请先添加合作旅行社。" : "请尝试其他代码或名称。")
                    )
                } else {
                    ForEach(matches) { agency in
                        Button {
                            onSelect(agency)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(agency.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text("\(agency.agencyCode) · \(agency.contactPerson.isEmpty ? "未填写联系人" : agency.contactPerson)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索旅行社代码或名称")
            .navigationTitle("选择旅行社")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

@MainActor
private struct OnlineContactDraft: Identifiable {
    let id = UUID()
    let remoteID: String?
    var type: String
    var value: String
    var isDefault: Bool

    init(type: String = "电话", value: String = "", isDefault: Bool = false, remoteID: String? = nil) {
        self.type = type
        self.value = value
        self.isDefault = isDefault
        self.remoteID = remoteID
    }

    init(_ record: CloudOnlineRepository.ContactRecord) {
        self.init(type: record.label.isEmpty ? record.contactType : record.label, value: record.value,
                  isDefault: record.isDefault, remoteID: record.id)
    }
}

@MainActor
private struct OnlineAddressDraft: Identifiable {
    let id = UUID()
    let remoteID: String?
    var label: String
    var value: String
    var isDefault: Bool

    init(label: String = "家", value: String = "", isDefault: Bool = false, remoteID: String? = nil) {
        self.label = label
        self.value = value
        self.isDefault = isDefault
        self.remoteID = remoteID
    }

    init(_ record: CloudOnlineRepository.AddressRecord) {
        self.init(label: record.label, value: record.address, isDefault: record.isDefault, remoteID: record.id)
    }
}

private struct OnlineCustomerAvatar: View {
    @Environment(AuthViewModel.self) private var auth
    let customer: CloudOnlineRepository.CustomerRecord?
    let directory: CloudCustomerDirectoryModel
    let size: CGFloat
    var fallbackName: String = ""
    @State private var imageData: Data?

    private var path: String { customer?.avatarURL ?? "" }
    private var name: String { fallbackName.isEmpty ? customer?.name ?? "?" : fallbackName }

    var body: some View {
        CustomerAvatarImage(data: imageData, name: name, size: size)
        .task(id: path) {
            guard !path.isEmpty else { imageData = nil; return }
            imageData = await directory.loadAvatarData(path: path, using: auth)
        }
    }
}

private extension String {
    var customerDisplayDate: String {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractionalFormatter.date(from: self) ?? ISO8601DateFormatter().date(from: self)
        return date?.formatted(date: .abbreviated, time: .omitted) ?? self
    }
}

private func formatCustomerCurrency(_ value: Double, code: String) -> String {
    let countryCode = BaseCurrencyCatalog.options.first { $0.currencyCode == code.uppercased() }?.countryCode
        ?? BaseCurrencyCatalog.defaultCountryCode
    return BaseCurrencyCatalog.format(value, countryCode: countryCode)
}
