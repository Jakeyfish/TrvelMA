import SwiftUI

struct CloudTravelAgencyDirectoryView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var directory = CloudTravelAgencyDirectoryModel()
    @State private var searchText = ""
    @State private var isAdding = false

    private var visibleAgencies: [CloudOnlineRepository.TravelAgencyRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return directory.agencies }
        return directory.agencies.filter {
            [$0.agencyCode, $0.name, $0.contactPerson, $0.phone]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if directory.isLoading && directory.agencies.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = directory.errorMessage, directory.agencies.isEmpty {
                    ContentUnavailableView {
                        Label("无法载入旅行社", systemImage: "icloud.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") { Task { await directory.reload(using: auth) } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField("搜索旅行社代码、名称或联系人", text: $searchText)
                                    .keyboardDoneToolbar()
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                if !searchText.isEmpty {
                                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                        .accessibilityLabel("清除搜索")
                                }
                            }
                            .padding(.horizontal, 14).frame(minHeight: 46)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

                            LazyVStack(spacing: 10) {
                                ForEach(visibleAgencies) { agency in
                                    NavigationLink { CloudTravelAgencyDetailView(agency: agency, directory: directory) } label: {
                                        CloudTravelAgencyCard(agency: agency)
                                    }.buttonStyle(.plain)
                                }
                                if visibleAgencies.isEmpty {
                                    ContentUnavailableView(searchText.isEmpty ? "暂无合作旅行社" : "没有找到旅行社",
                                                           systemImage: searchText.isEmpty ? "building.2" : "magnifyingglass",
                                                           description: Text(searchText.isEmpty ? "点击右上角加号添加旅行社。" : "请尝试其他代码、名称或联系人。"))
                                        .padding(.top, 22)
                                }
                            }
                        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 28)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .background(Color(.systemGroupedBackground))
                    .refreshable { await directory.reload(using: auth) }
                }
            }
            .navigationTitle("合作旅行社")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isAdding = true } label: {
                        Image(systemName: "plus").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white).frame(width: 34, height: 34).background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                        .disabled(directory.isLoading)
                }
            }
            .adaptiveFormPresentation(isPresented: $isAdding) {
                NavigationStack { CloudTravelAgencyEditor(directory: directory, agency: nil) }
            }
            .task(id: "\(auth.isCloudAccount)|\(auth.currentEmail)") {
                directory.clearForAccountChange()
                await directory.reload(using: auth)
            }
            .alert("无法更新旅行社目录", isPresented: Binding(
                get: { directory.errorMessage != nil && !directory.agencies.isEmpty },
                set: { if !$0 { directory.clearError() } }
            )) {
                Button("确定", role: .cancel) { directory.clearError() }
            } message: {
                Text(directory.errorMessage ?? "")
            }
        }
    }
}

private struct CloudTravelAgencyCard: View {
    let agency: CloudOnlineRepository.TravelAgencyRecord

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "building.2.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.accentColor)
                .frame(width: 48, height: 48).background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(agency.name).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(agency.agencyCode).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Color.accentColor).lineLimit(1)
                }
                if !agency.contactPerson.isEmpty || !agency.phone.isEmpty {
                    HStack(spacing: 12) {
                        if !agency.contactPerson.isEmpty { Label(agency.contactPerson, systemImage: "person").lineLimit(1) }
                        if !agency.phone.isEmpty { Label(agency.phone, systemImage: "phone").lineLimit(1) }
                    }.font(.footnote).foregroundStyle(.secondary)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(Color.secondary.opacity(0.14), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct CloudTravelAgencyDetailView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let agency: CloudOnlineRepository.TravelAgencyRecord
    let directory: CloudTravelAgencyDirectoryModel
    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "building.2.fill").font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.accentColor)
                        .frame(width: 64, height: 64).background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(agency.name).font(.title3.weight(.bold))
                        Text("代码：\(agency.agencyCode)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 12) {
                    agencyDetailValue("联系人", agency.contactPerson.isEmpty ? "未填写" : agency.contactPerson)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("联系电话").font(.caption).foregroundStyle(.secondary)
                        if agency.phone.isEmpty { Text("未填写").font(.subheadline).foregroundStyle(.secondary) }
                        else {
                            Button(agency.phone) { openContactURL("tel://\(agency.phone)") }
                                .font(.subheadline).foregroundStyle(Color.accentColor).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 3)
                LabeledContent("办公地址", value: agency.officeAddress.isEmpty ? "未填写" : agency.officeAddress)
            }
        }
        .navigationTitle("旅行社资料")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isEditing = true } label: { Label("编辑", systemImage: "pencil") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { isConfirmingDelete = true } label: { Image(systemName: "trash") }
                    .accessibilityLabel("删除旅行社")
            }
        }
        .adaptiveFormPresentation(isPresented: $isEditing) {
            NavigationStack { CloudTravelAgencyEditor(directory: directory, agency: agency) }
        }
        .confirmationDialog("确定删除该旅行社？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task { if await directory.delete(id: agency.id, using: auth) { dismiss() } }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("无法删除旅行社", isPresented: Binding(
            get: { directory.errorMessage != nil },
            set: { if !$0 { directory.clearError() } }
        )) {
            Button("确定", role: .cancel) { directory.clearError() }
        } message: {
            Text(directory.errorMessage ?? "")
        }
    }

    private func agencyDetailValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8) }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openContactURL(_ value: String) {
        let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        if let url = URL(string: encoded) { openURL(url) }
    }
}

@MainActor
private struct CloudTravelAgencyEditor: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let directory: CloudTravelAgencyDirectoryModel
    let agency: CloudOnlineRepository.TravelAgencyRecord?
    @State private var code: String
    @State private var name: String
    @State private var contact: String
    @State private var phone: String
    @State private var address: String
    @State private var validationError: String?

    init(directory: CloudTravelAgencyDirectoryModel, agency: CloudOnlineRepository.TravelAgencyRecord?) {
        self.directory = directory
        self.agency = agency
        _code = State(initialValue: agency?.agencyCode ?? "")
        _name = State(initialValue: agency?.name ?? "")
        _contact = State(initialValue: agency?.contactPerson ?? "")
        _phone = State(initialValue: agency?.phone ?? "")
        _address = State(initialValue: agency?.officeAddress ?? "")
    }

    var body: some View {
        Form {
            Section {
                requiredField("旅行社代码", placeholder: "请输入旅行社代码", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                requiredField("旅行社名称", placeholder: "请输入旅行社名称", text: $name)
                    .nativeIMEInput()
            } header: {
                Text("基本信息（* 为必填项）")
            }

            Section("联系信息") {
                HStack(spacing: 12) {
                    TextField("联系人", text: $contact)
                    SystemIMETextField(
                        text: $phone,
                        placeholder: "联系电话",
                        keyboardType: .phonePad,
                        textContentType: .telephoneNumber
                    )
                }
                TextField("办公地址", text: $address, axis: .vertical)
                    .lineLimit(2...4)
                    .nativeIMEInput()
            }
        }
        .keyboardDoneToolbar()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(agency == nil ? "新增旅行社" : "编辑旅行社")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { Task { await save() } }
                    .fontWeight(.semibold)
                    .disabled(directory.isSaving)
            }
        }
        .overlay {
            if directory.isSaving { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) }
        }
        .alert("无法保存", isPresented: Binding(
            get: { validationError != nil || directory.errorMessage != nil },
            set: {
                if !$0 {
                    validationError = nil
                    directory.clearError()
                }
            }
        )) {
            Button("确定", role: .cancel) {
                validationError = nil
                directory.clearError()
            }
        } message: {
            Text(validationError ?? directory.errorMessage ?? "")
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

    private func save() async {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { validationError = "请填写旅行社代码"; return }
        guard !trimmedName.isEmpty else { validationError = "请填写旅行社名称"; return }
        let saved = await directory.save(
            id: agency?.id ?? UUID().uuidString.lowercased(),
            agencyCode: trimmedCode,
            name: trimmedName,
            contactPerson: contact.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            officeAddress: address.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: agency?.creationDate ?? .now,
            using: auth
        )
        if saved { dismiss() }
    }
}
