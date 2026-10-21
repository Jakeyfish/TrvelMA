import SwiftUI
import SwiftData
import PhotosUI
import UIKit

private struct BusinessCardQR: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var imageData: Data?
}

private struct BusinessCardDraft: Codable, Equatable {
    var nickname = ""
    var style = 0
    var portraitData: Data?
    var qrCodes: [BusinessCardQR] = []
}

struct BusinessCardView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.locale) private var locale
    @Query private var accounts: [LocalAccount]
    @State private var draft = BusinessCardDraft()
    @State private var persistedDraft: BusinessCardDraft?
    @State private var portraitPicker: PhotosPickerItem?
    @State private var hasLoaded = false

    private var account: LocalAccount? {
        accounts.first { $0.email.localizedCaseInsensitiveCompare(auth.currentEmail) == .orderedSame }
    }

    private var registeredName: String {
        let name = auth.currentSalutation.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未填写" : name
    }

    private var registeredPhone: String {
        let phone = (account?.phone ?? auth.currentPhone).trimmingCharacters(in: .whitespacesAndNewlines)
        return phone.isEmpty ? "未填写" : phone
    }

    private var assetNamespace: AccountAssetStore.Namespace { auth.isCloudAccount ? .cloud : .local }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    photoPicker
                    registeredInformation
                    nicknameField
                    stylePicker
                    BusinessCardPreview(
                        name: registeredName,
                        phone: registeredPhone,
                        email: auth.currentEmail.isEmpty ? "未填写" : auth.currentEmail,
                        nickname: draft.nickname,
                        portraitData: draft.portraitData,
                        style: draft.style
                    )
                    qrCodeSection
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("名片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { saveDraft() }
                        .fontWeight(.semibold)
                }
            }
            .task(id: "\(auth.isCloudAccount)|\(auth.currentEmail)") { loadDraft() }
            .onChange(of: portraitPicker) { _, item in
                Task { await loadPortrait(item) }
            }
            .onChange(of: draft) { _, _ in
                if hasLoaded, draft != persistedDraft { saveDraft() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .accountAssetsDidSync)) { _ in
                loadDraft()
            }
            .onReceive(NotificationCenter.default.publisher(for: .accountScopedLocalDataDidClear)) { notification in
                guard (notification.object as? String) == DataOwnership.activeScope else { return }
                loadDraft()
            }
        }
    }

    private var photoPicker: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $portraitPicker, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let data = draft.portraitData, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Circle()
                                .fill(Color.accentColor.opacity(0.10))
                                .overlay {
                                    VStack(spacing: 8) {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.system(size: 50, weight: .light))
                                    }
                                    .foregroundStyle(Color.accentColor)
                                }
                        }
                    }
                    .frame(width: 124, height: 124)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.accentColor.opacity(0.24), lineWidth: 1))
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(Color.accentColor, in: Circle())
                        .overlay(Circle().stroke(Color(.systemGroupedBackground), lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("选择名片头像")
            Text("头像")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var registeredInformation: some View {
        VStack(alignment: .leading, spacing: 10) {
            readOnlyRow(title: "姓名", value: registeredName, icon: "person")
            readOnlyRow(title: "电话", value: registeredPhone, icon: "phone")
            readOnlyRow(title: "电子邮箱", value: auth.currentEmail.isEmpty ? "未填写" : auth.currentEmail, icon: "envelope")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func readOnlyRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 5)
    }

    private var nicknameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("昵称")
                .font(.headline)
            TextField("输入名片上显示的昵称", text: $draft.nickname)
                .keyboardDoneToolbar()
                .textInputAutocapitalization(.words)
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("名片样式")
                .font(.headline)
            HStack(spacing: 10) {
                styleButton(index: 0, title: "样式一", subtitle: "简洁平版", icon: "rectangle")
                styleButton(index: 1, title: "样式二", subtitle: "金属质感", icon: "rectangle.inset.filled")
            }
        }
    }

    private func styleButton(index: Int, title: String, subtitle: String, icon: String) -> some View {
        Button { draft.style = index } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(draft.style == index ? Color.accentColor : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .padding(12)
            .background(draft.style == index ? Color.accentColor.opacity(0.10) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(draft.style == index ? Color.accentColor : Color.secondary.opacity(0.12), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var qrCodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("二维码")
                        .font(.headline)
                    Text("添加微信、LINE 或其他联系二维码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    draft.qrCodes.append(BusinessCardQR(name: String(localized: "新二维码", locale: locale)))
                } label: {
                    Label("添加", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            ForEach($draft.qrCodes) { $item in
                BusinessCardQRRow(item: $item) {
                    draft.qrCodes.removeAll { $0.id == item.id }
                }
            }
            if draft.qrCodes.isEmpty {
                ContentUnavailableView("还没有二维码", systemImage: "qrcode", description: Text("点“添加”后选择二维码图片并填写名称。"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @MainActor
    private func loadPortrait(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.86) else { return }
        draft.portraitData = jpeg
    }

    private func loadDraft() {
        guard !auth.currentEmail.isEmpty else { return }
        if !auth.isCloudAccount {
            AccountAssetStore.migrateLegacyAssetsToLocal(email: auth.currentEmail)
        }
        if let data = AccountAssetStore.data(for: .businessCard, email: auth.currentEmail, namespace: assetNamespace),
           let saved = try? JSONDecoder().decode(BusinessCardDraft.self, from: data) {
            draft = saved
        } else {
            draft = BusinessCardDraft()
        }
        persistedDraft = draft
        hasLoaded = true
    }

    private func saveDraft() {
        guard !auth.currentEmail.isEmpty,
              let data = try? JSONEncoder().encode(draft) else { return }
        AccountAssetStore.set(data, for: .businessCard, email: auth.currentEmail, namespace: assetNamespace)
        persistedDraft = draft
        NotificationCenter.default.post(name: .accountAssetsDidChange, object: nil)
    }
}

private struct BusinessCardQRRow: View {
    @Environment(\.locale) private var locale
    @Binding var item: BusinessCardQR
    var onDelete: () -> Void
    @State private var pickerItem: PhotosPickerItem?
    @State private var isShowingPreview = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = item.imageData, let image = UIImage(data: data) {
                    Button { isShowingPreview = true } label: {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "浏览\(item.name)二维码", locale: locale))
                } else {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择二维码图片")
                }
            }
            .frame(width: 68, height: 68)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("二维码名称")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("例如：微信", text: $item.name)
                    .keyboardDoneToolbar()
                    .textFieldStyle(.roundedBorder)
            }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .sheet(isPresented: $isShowingPreview) {
            NavigationStack {
                Group {
                    if let data = item.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(20)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground))
                    }
                }
                .navigationTitle(item.name.isEmpty ? "二维码" : item.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if let data = item.imageData, let image = UIImage(data: data) {
                            ShareLink(
                                item: Image(uiImage: image),
                                preview: SharePreview(item.name.isEmpty ? "二维码" : item.name, image: Image(uiImage: image))
                            ) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .accessibilityLabel("分享二维码")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { isShowingPreview = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self), UIImage(data: data) != nil {
                    item.imageData = data
                }
            }
        }
    }
}

private struct BusinessCardPreview: View {
    let name: String
    let phone: String
    let email: String
    let nickname: String
    let portraitData: Data?
    let style: Int

    private var isMetallic: Bool { style == 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                portrait
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(isMetallic ? 0.45 : 0.7), lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text(nickname.isEmpty ? name : nickname)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                    if !nickname.isEmpty {
                        Text(name).font(.caption).opacity(0.78)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "person.text.rectangle.fill")
                    .font(.title2)
                    .opacity(0.72)
            }
            Rectangle().fill(.white.opacity(isMetallic ? 0.35 : 0.5)).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                Label(phone, systemImage: "phone.fill")
                Label(email, systemImage: "envelope.fill")
            }
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .foregroundStyle(isMetallic ? Color.white : Color(red: 0.24, green: 0.20, blue: 0.16))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isMetallic
                      ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.66, green: 0.57, blue: 0.42), Color(red: 0.24, green: 0.26, blue: 0.28), Color(red: 0.58, green: 0.48, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(LinearGradient(colors: [Color.white, Color(red: 0.97, green: 0.93, blue: 0.86)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(isMetallic ? Color.white.opacity(0.4) : Color.accentColor.opacity(0.18), lineWidth: 1))
                .shadow(color: isMetallic ? .black.opacity(0.2) : .brown.opacity(0.1), radius: isMetallic ? 12 : 7, x: 0, y: isMetallic ? 8 : 4)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var portrait: some View {
        if let portraitData, let image = UIImage(data: portraitData) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.white.opacity(isMetallic ? 0.2 : 0.72))
                .overlay(Image(systemName: "person.fill").font(.title2).foregroundStyle(isMetallic ? .white : Color.accentColor))
        }
    }
}
