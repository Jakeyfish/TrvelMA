import SwiftUI
import SwiftData

struct TravelAgencySelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var agencies: [TravelAgency]
    @State private var searchText = ""
    let onSelect: (TravelAgency) -> Void

    init(onSelect: @escaping (TravelAgency) -> Void) {
        self.onSelect = onSelect
        let scope = DataOwnership.activeScope
        _agencies = Query(filter: #Predicate { $0.ownerScope == scope })
    }

    private var matchingAgencies: [TravelAgency] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return agencies
            .filter { query.isEmpty || [$0.agencyCode, $0.name, $0.contactPerson, $0.phone].contains { $0.localizedCaseInsensitiveContains(query) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                if matchingAgencies.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "暂无合作旅行社" : "没有找到旅行社",
                        systemImage: searchText.isEmpty ? "building.2" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "请先在头像菜单的“合作旅行社”中添加旅行社。" : "请尝试其他代码或名称。")
                    )
                } else {
                    ForEach(matchingAgencies, id: \.uuid) { agency in
                        Button {
                            onSelect(agency)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "building.2.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 38, height: 38)
                                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(agency.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text("\(agency.agencyCode) · \(agency.contactPerson.isEmpty ? "未填写联系人" : agency.contactPerson)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索旅行社代码或名称")
            .navigationTitle("选择旅行社")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct TravelAgencyListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var agencies: [TravelAgency]
    @State private var searchText = ""
    @State private var isAddingAgency = false

    init() {
        let scope = DataOwnership.activeScope
        _agencies = Query(filter: #Predicate { $0.ownerScope == scope })
    }

    private var filteredAgencies: [TravelAgency] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return agencies
            .filter { query.isEmpty || [$0.agencyCode, $0.name, $0.contactPerson, $0.phone, $0.officeAddress].contains { $0.localizedCaseInsensitiveContains(query) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索旅行社代码、名称或联系人", text: $searchText)
                            .keyboardDoneToolbar()
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("清除搜索")
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                    LazyVStack(spacing: 10) {
                        ForEach(filteredAgencies, id: \.uuid) { agency in
                            NavigationLink {
                                TravelAgencyBrowseView(agency: agency)
                            } label: {
                                TravelAgencyCard(agency: agency)
                            }
                            .buttonStyle(.plain)
                        }

                        if filteredAgencies.isEmpty {
                            ContentUnavailableView(
                                searchText.isEmpty ? "暂无合作旅行社" : "没有找到旅行社",
                                systemImage: searchText.isEmpty ? "building.2" : "magnifyingglass",
                                description: Text(searchText.isEmpty ? "点击右上角加号添加旅行社。" : "请尝试其他代码、名称或联系人。")
                            )
                            .padding(.top, 22)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("合作旅行社")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAddingAgency = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新增旅行社")
                }
            }
            .adaptiveFormPresentation(isPresented: $isAddingAgency) {
                NavigationStack {
                    TravelAgencyEditView(agency: nil)
                }
            }
        }
        .font(.system(size: 15))
    }
}

private struct TravelAgencyCard: View {
    let agency: TravelAgency

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(agency.name).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(agency.agencyCode)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
                if !agency.contactPerson.isEmpty || !agency.phone.isEmpty {
                    HStack(spacing: 12) {
                        if !agency.contactPerson.isEmpty {
                            Label(agency.contactPerson, systemImage: "person")
                                .lineLimit(1)
                        }
                        if !agency.phone.isEmpty {
                            Label(agency.phone, systemImage: "phone")
                                .lineLimit(1)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.secondary.opacity(0.14), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct TravelAgencyBrowseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let agency: TravelAgency
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    private func agencyDetailValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "building.2.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 64, height: 64)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(agency.name).font(.title3.weight(.bold))
                        Text("代码：\(agency.agencyCode)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    agencyDetailValue("联系人", agency.contactPerson.isEmpty ? "未填写" : agency.contactPerson)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("联系电话").font(.caption).foregroundStyle(.secondary)
                        if agency.phone.isEmpty {
                            Text("未填写").font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            Button(agency.phone) {
                                let encoded = agency.phone.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? agency.phone
                                if let url = URL(string: "tel://\(encoded)") { openURL(url) }
                            }
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 3)
                LabeledContent("办公地址", value: agency.officeAddress.isEmpty ? "未填写" : agency.officeAddress)
            }
        }
        .navigationTitle("旅行社资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { isEditing = true } label: { Label("编辑", systemImage: "pencil") }
                Button(role: .destructive) { isConfirmingDelete = true } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("删除旅行社")
            }
        }
        .adaptiveFormPresentation(isPresented: $isEditing) {
            NavigationStack { TravelAgencyEditView(agency: agency) }
        }
        .confirmationDialog("确定删除该旅行社？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteAgency() }
            Button("取消", role: .cancel) {}
        }
        .alert("提示", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func deleteAgency() {
        SupabaseDataSync.recordDeletion(table: "travel_agencies", id: agency.uuid, context: modelContext)
        modelContext.delete(agency)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TravelAgencyEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    private let agency: TravelAgency?
    @State private var agencyCode: String
    @State private var name: String
    @State private var contactPerson: String
    @State private var phone: String
    @State private var officeAddress: String
    @State private var errorMessage: String?

    init(agency: TravelAgency?) {
        self.agency = agency
        _agencyCode = State(initialValue: agency?.agencyCode ?? "")
        _name = State(initialValue: agency?.name ?? "")
        _contactPerson = State(initialValue: agency?.contactPerson ?? "")
        _phone = State(initialValue: agency?.phone ?? "")
        _officeAddress = State(initialValue: agency?.officeAddress ?? "")
    }

    var body: some View {
        Form {
            Section {
                requiredField("旅行社代码", placeholder: "请输入旅行社代码", text: $agencyCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                requiredField("旅行社名称", placeholder: "请输入旅行社名称", text: $name)
                    .nativeIMEInput()
            } header: {
                Text("基本信息（* 为必填项）")
            }

            Section("联系信息") {
                HStack(spacing: 12) {
                    TextField("联系人", text: $contactPerson)
                    SystemIMETextField(
                        text: $phone,
                        placeholder: "联系电话",
                        keyboardType: .phonePad,
                        textContentType: .telephoneNumber
                    )
                }
                TextField("办公地址", text: $officeAddress, axis: .vertical)
                    .lineLimit(2...4)
                    .nativeIMEInput()
            }
        }
        .keyboardDoneToolbar()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(agency == nil ? "新增旅行社" : "编辑旅行社")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { saveAgency() }
                    .fontWeight(.semibold)
            }
        }
        .alert("无法保存", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func requiredField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 3) {
                Text(LocalizedStringKey(title)).foregroundStyle(.primary)
                Text("*").foregroundStyle(.red).accessibilityLabel("必填")
            }
            TextField(LocalizedStringKey(placeholder), text: text)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 3)
    }

    private func saveAgency() {
        let code = agencyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let agencyName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { errorMessage = "请填写旅行社代码"; return }
        guard !agencyName.isEmpty else { errorMessage = "请填写旅行社名称"; return }

        let record: TravelAgency
        if let agency {
            record = agency
        } else {
            record = TravelAgency(agencyCode: code, name: agencyName)
            modelContext.insert(record)
        }
        record.agencyCode = code
        record.name = agencyName
        record.contactPerson = contactPerson.trimmingCharacters(in: .whitespacesAndNewlines)
        record.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        record.officeAddress = officeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        record.updateAt = .now
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
