import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import UniformTypeIdentifiers

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

private enum BusinessCardCopy {
    static func text(_ key: String, language: AppLanguage) -> String {
        switch key {
        case "名片页面标题": return value(language, "名片", "名片", "Business Card", "Tarjeta de presentación", "名刺", "명함")
        case "名片资料格式无效，已保留当前内容。": return value(language, "名片资料格式无效，已保留当前内容。", "名片資料格式無效，已保留目前內容。", "Business card data is invalid. Your current content has been kept.", "Los datos de la tarjeta no son válidos. Se ha conservado el contenido actual.", "名刺データの形式が無効です。現在の内容は保持されています。", "명함 데이터 형식이 잘못되었습니다. 현재 내용은 유지되었습니다.")
        case "保存": return value(language, "保存", "儲存", "Save", "Guardar", "保存", "저장")
        case "头像": return value(language, "头像", "大頭貼", "Profile Photo", "Foto de perfil", "プロフィール写真", "프로필 사진")
        case "选择名片头像": return value(language, "选择名片头像", "選擇名片大頭貼", "Choose business card photo", "Elegir foto de tarjeta", "名刺の写真を選択", "명함 사진 선택")
        case "姓名": return value(language, "姓名", "姓名", "Name", "Nombre", "名前", "이름")
        case "电话": return value(language, "电话", "電話", "Phone", "Teléfono", "電話", "전화")
        case "电子邮箱": return value(language, "电子邮箱", "電子郵件", "Email", "Correo electrónico", "メールアドレス", "이메일")
        case "未填写": return value(language, "未填写", "未填寫", "Not provided", "Sin indicar", "未入力", "입력되지 않음")
        case "昵称": return value(language, "昵称", "暱稱", "Nickname", "Apodo", "ニックネーム", "별명")
        case "输入名片上显示的昵称": return value(language, "输入名片上显示的昵称", "輸入名片上顯示的暱稱", "Enter the nickname shown on your card", "Introduce el apodo que se mostrará en la tarjeta", "名刺に表示するニックネームを入力", "명함에 표시할 별명을 입력하세요")
        case "名片样式": return value(language, "名片样式", "名片樣式", "Business Card Style", "Estilo de tarjeta", "名刺のスタイル", "명함 스타일")
        case "样式一": return value(language, "样式一", "樣式一", "Style 1", "Estilo 1", "スタイル 1", "스타일 1")
        case "简洁平版": return value(language, "简洁平版", "簡潔平版", "Classic", "Clásico", "シンプル", "심플")
        case "样式二": return value(language, "样式二", "樣式二", "Style 2", "Estilo 2", "スタイル 2", "스타일 2")
        case "金属质感": return value(language, "金属质感", "金屬質感", "Metallic", "Metálico", "メタリック", "메탈릭")
        case "二维码": return value(language, "其他资料", "其他資料", "Other materials", "Otros materiales", "その他の資料", "기타 자료")
        case "添加微信、LINE 或其他联系二维码": return value(language, "添加二维码、服务介绍等图片资料", "新增 QR Code、服務介紹等圖片資料", "Add QR codes, service information, or other images", "Añade códigos QR, información de servicios u otras imágenes", "QRコードやサービス紹介などの画像を追加", "QR 코드, 서비스 소개 등 이미지 추가")
        case "添加": return value(language, "添加", "新增", "Add", "Añadir", "追加", "추가")
        case "新二维码": return value(language, "新资料", "新資料", "New material", "Nuevo material", "新しい資料", "새 자료")
        case "还没有二维码": return value(language, "还没有其他资料", "尚無其他資料", "No materials yet", "Aún no hay materiales", "資料はまだありません", "아직 자료가 없습니다")
        case "点“添加”后选择二维码图片并填写名称。": return value(language, "点“添加”后选择图片并填写名称。", "點選「新增」後選擇圖片並輸入名稱。", "Tap Add to choose an image and enter its name.", "Pulsa Añadir para elegir una imagen e introducir su nombre.", "「追加」をタップして画像を選び、名前を入力します。", "추가를 눌러 이미지를 선택하고 이름을 입력하세요.")
        case "二维码名称": return value(language, "资料名称", "資料名稱", "Material name", "Nombre del material", "資料名", "자료 이름")
        case "例如：微信": return value(language, "例如：微信", "例如：微信", "e.g. WeChat", "p. ej., WeChat", "例：WeChat", "예: WeChat")
        case "选择二维码图片": return value(language, "选择资料图片", "選擇資料圖片", "Choose material image", "Elegir imagen", "資料画像を選択", "자료 이미지 선택")
        case "分享二维码": return value(language, "分享资料", "分享資料", "Share material", "Compartir material", "資料を共有", "자료 공유")
        case "完成": return value(language, "完成", "完成", "Done", "Listo", "完了", "완료")
        case "请填写昵称": return value(language, "请填写昵称", "請填寫暱稱", "Please enter a nickname", "Introduce un apodo", "ニックネームを入力", "별명을 입력하세요")
        case "保存图片": return value(language, "保存图片", "儲存圖片", "Save image", "Guardar imagen", "画像を保存", "이미지 저장")
        case "分享名片": return value(language, "分享名片", "分享名片", "Share card", "Compartir tarjeta", "名刺を共有", "명함 공유")
        case "无法生成名片图片，请重试。": return value(language, "无法生成名片图片，请重试。", "無法產生名片圖片，請重試。", "Unable to create the card image. Please try again.", "No se pudo crear la imagen. Inténtalo de nuevo.", "名刺画像を作成できません。再試行してください。", "명함 이미지를 생성할 수 없습니다. 다시 시도하세요.")
        default:
            return String(localized: String.LocalizationValue(key), locale: Locale(identifier: language.rawValue))
        }
    }

    private static func value(_ language: AppLanguage, _ simplified: String, _ traditional: String, _ english: String, _ spanish: String, _ japanese: String, _ korean: String) -> String {
        switch language {
        case .simplifiedChinese: simplified
        case .traditionalChinese: traditional
        case .english: english
        case .spanish: spanish
        case .japanese: japanese
        case .korean: korean
        }
    }
}

struct BusinessCardView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppLanguageSettings.self) private var languageSettings
    @Query private var accounts: [LocalAccount]
    @State private var draft = BusinessCardDraft()
    @State private var persistedDraft: BusinessCardDraft?
    @State private var portraitPicker: PhotosPickerItem?
    @State private var portraitLoadTask: Task<Void, Never>?
    @State private var loadedDraftAccountKey: String?
    @State private var exportImage: UIImage?
    @State private var exportDocument = BusinessCardImageDocument(data: Data())
    @State private var showsImageExporter = false
    @State private var showsCardShare = false
    @State private var exportError: String?
    @State private var hasLoaded = false
    @State private var draftLoadGeneration = 0
    @State private var cloudAssetModel = CloudAccountAssetModel()

    private var account: LocalAccount? {
        accounts.first { $0.email.localizedCaseInsensitiveCompare(auth.currentEmail) == .orderedSame }
    }

    private var registeredName: String {
        let name = auth.currentSalutation.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? localized("未填写") : name
    }

    private var registeredPhone: String {
        let phone = (account?.phone ?? auth.currentPhone).trimmingCharacters(in: .whitespacesAndNewlines)
        return phone.isEmpty ? localized("未填写") : phone
    }

    private var draftAccountKey: String {
        "\(auth.isCloudAccount ? "cloud" : "local")|\(auth.currentEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private var assetNamespace: AccountAssetStore.Namespace { auth.isCloudAccount ? .cloud : .local }

    private func localized(_ key: String) -> String {
        BusinessCardCopy.text(key, language: languageSettings.selectedLanguage)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    photoPicker
                    registeredInformation
                    nicknameField
                    stylePicker
                    cardPreview
                    HStack {
                        Button { prepareCardExport(share: false) } label: { Label(localized("保存图片"), systemImage: "square.and.arrow.down") }
                        Spacer()
                        Button { prepareCardExport(share: true) } label: { Label(localized("分享名片"), systemImage: "square.and.arrow.up") }
                    }.buttonStyle(.bordered).disabled(!hasLoaded)
                    qrCodeSection
                }
                .padding(16)
                .disabled(!hasLoaded)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text(localized("名片页面标题")).font(.system(size: 30, weight: .bold, design: .rounded))
                    Spacer()
                    Button(localized("保存")) { Task { await saveDraft() } }.disabled(cloudAssetModel.isSaving || !hasLoaded)
                }.frame(minHeight: 52).padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
            }
            .toolbar(.hidden, for: .navigationBar)
            .fileExporter(isPresented: $showsImageExporter, document: exportDocument, contentType: .png, defaultFilename: "TrvelMA-Business-Card") { result in
                if case .failure(let error) = result { exportError = error.localizedDescription }
            }
            .sheet(isPresented: $showsCardShare, onDismiss: { exportImage = nil }) {
                if let exportImage { BusinessCardShareSheet(image: exportImage) }
            }
            .alert(localized("名片页面标题"), isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
                Button(localized("完成"), role: .cancel) { exportError = nil }
            } message: { Text(exportError ?? "") }
            .task(id: "\(auth.isCloudAccount)|\(auth.currentEmail)") {
                exportImage = nil
                showsCardShare = false
                showsImageExporter = false
                exportDocument = BusinessCardImageDocument(data: Data())
                cloudAssetModel.beginAccountChange()
                portraitLoadTask?.cancel()
                portraitLoadTask = nil
                portraitPicker = nil
                loadedDraftAccountKey = nil
                hasLoaded = false
                draft = BusinessCardDraft()
                persistedDraft = nil
                await loadDraft()
            }
            .onChange(of: portraitPicker) { _, item in
                portraitLoadTask?.cancel()
                portraitLoadTask = nil
                if item != nil { portraitLoadTask = Task { await loadPortrait(item) } }
            }
            .onChange(of: draft) { _, _ in
                if !auth.isCloudAccount, hasLoaded, draft != persistedDraft { Task { await saveDraft() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .accountAssetsDidSync)) { _ in
                Task { await loadDraft() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .accountScopedLocalDataDidClear)) { notification in
                guard (notification.object as? String) == DataOwnership.activeScope else { return }
                portraitLoadTask?.cancel()
                portraitLoadTask = nil
                portraitPicker = nil
                loadedDraftAccountKey = nil
                hasLoaded = false
                draft = BusinessCardDraft()
                persistedDraft = nil
                Task { await loadDraft() }
            }
            .alert(localized("名片页面标题"), isPresented: Binding(
                get: { cloudAssetModel.errorMessage != nil },
                set: { if !$0 { cloudAssetModel.clearError() } }
            )) {
                Button(localized("完成"), role: .cancel) { cloudAssetModel.clearError() }
            } message: {
                Text(cloudAssetModel.errorMessage ?? "")
            }
        }
    }

    private var cardPreview: some View {
        BusinessCardPreview(name: registeredName, phone: registeredPhone,
            email: auth.currentEmail.trimmingCharacters(in: .whitespacesAndNewlines), nickname: draft.nickname,
            portraitData: draft.portraitData, qrCodeData: draft.qrCodes.first(where: { $0.imageData != nil })?.imageData, style: draft.style)
    }

    @MainActor private func prepareCardExport(share: Bool) {
        guard hasLoaded, loadedDraftAccountKey == draftAccountKey else { return }
        let renderer = ImageRenderer(content: cardPreview.frame(width: 600).padding(20).background(Color.white)
            .environment(\.colorScheme, .light).environment(\.locale, languageSettings.locale))
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.pngData() else {
            exportError = localized("无法生成名片图片，请重试。"); return
        }
        exportImage = image
        exportDocument = BusinessCardImageDocument(data: data)
        if share { showsCardShare = true } else { showsImageExporter = true }
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
            .accessibilityLabel(localized("选择名片头像"))
            Text(localized("头像"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var registeredInformation: some View {
        VStack(alignment: .leading, spacing: 10) {
            readOnlyRow(title: "姓名", value: registeredName, icon: "person")
            readOnlyRow(title: "电话", value: registeredPhone, icon: "phone")
            readOnlyRow(title: "电子邮箱", value: auth.currentEmail.isEmpty ? localized("未填写") : auth.currentEmail, icon: "envelope")
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
            Text(localized(title))
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
            Text(localized("昵称"))
                .font(.headline)
            SystemIMETextField(
                text: $draft.nickname,
                placeholder: localized("输入名片上显示的昵称"),
                capitalization: .words
            )
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("名片样式"))
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
                Text(localized(title)).font(.subheadline.weight(.semibold))
                Text(localized(subtitle)).font(.caption).foregroundStyle(.secondary)
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
                    Text(localized("二维码"))
                        .font(.headline)
                    Text(localized("添加微信、LINE 或其他联系二维码"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    draft.qrCodes.append(BusinessCardQR(name: localized("新二维码")))
                } label: {
                    Label(localized("添加"), systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            ForEach($draft.qrCodes) { $item in
                let rowID = item.id
                let accountKey = draftAccountKey
                BusinessCardQRRow(item: $item, onDelete: {
                    draft.qrCodes.removeAll { $0.id == rowID }
                }, onImageLoaded: { data in
                    applyQRCodeImage(data, to: rowID, accountKey: accountKey)
                })
            }
            if draft.qrCodes.isEmpty {
                ContentUnavailableView {
                    Label(localized("还没有二维码"), systemImage: "qrcode")
                } description: {
                    Text(localized("点“添加”后选择二维码图片并填写名称。"))
                }
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
        let accountKey = draftAccountKey
        guard hasLoaded, loadedDraftAccountKey == accountKey, let item, portraitPicker == item,
              let data = try? await item.loadTransferable(type: Data.self),
              !Task.isCancelled, portraitPicker == item,
              loadedDraftAccountKey == accountKey, draftAccountKey == accountKey,
              let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.86) else { return }
        draft.portraitData = jpeg
    }

    private func applyQRCodeImage(_ data: Data, to rowID: UUID, accountKey: String) {
        guard hasLoaded, loadedDraftAccountKey == accountKey, draftAccountKey == accountKey,
              let index = draft.qrCodes.firstIndex(where: { $0.id == rowID }) else { return }
        draft.qrCodes[index].imageData = data
    }

    private func loadDraft() async {
        guard !auth.currentEmail.isEmpty, !hasLoaded || draft == persistedDraft else { return }
        draftLoadGeneration += 1
        let generation = draftLoadGeneration
        let startingDraft = draft
        let startingPersistedDraft = persistedDraft
        let email = auth.currentEmail
        let wasCloudAccount = auth.isCloudAccount
        cloudAssetModel.clearError()
        let data: Data?
        if auth.serverEntitlement?.edition == .cloud {
            data = await cloudAssetModel.load(.businessCard, using: auth)
            guard !Task.isCancelled, auth.currentEmail.caseInsensitiveCompare(email) == .orderedSame,
                  auth.isCloudAccount == wasCloudAccount,
                  auth.serverEntitlement?.edition == .cloud,
                  draftLoadGeneration == generation,
                  draft == startingDraft, persistedDraft == startingPersistedDraft,
                  cloudAssetModel.errorMessage == nil else { return }
        } else {
            if !auth.isCloudAccount {
                AccountAssetStore.migrateLegacyAssetsToLocal(email: email)
            }
            data = AccountAssetStore.data(for: .businessCard, email: email, namespace: assetNamespace)
        }

        let loadedDraft: BusinessCardDraft
        if let data {
            guard let saved = try? JSONDecoder().decode(BusinessCardDraft.self, from: data) else {
                cloudAssetModel.setLoadError(localized("名片资料格式无效，已保留当前内容。"))
                return
            }
            loadedDraft = saved
        } else {
            loadedDraft = BusinessCardDraft()
        }
        draft = loadedDraft
        persistedDraft = loadedDraft
        loadedDraftAccountKey = draftAccountKey
        hasLoaded = true
    }

    private func saveDraft() async {
        let draftToSave = draft
        let accountKey = draftAccountKey
        guard hasLoaded, loadedDraftAccountKey == accountKey, !auth.currentEmail.isEmpty,
              let data = try? JSONEncoder().encode(draftToSave) else { return }
        if auth.serverEntitlement?.edition == .cloud {
            let email = auth.currentEmail
            if await cloudAssetModel.save(data, as: .businessCard, using: auth),
               auth.currentEmail.caseInsensitiveCompare(email) == .orderedSame,
               auth.serverEntitlement?.edition == .cloud,
               draftAccountKey == accountKey, loadedDraftAccountKey == accountKey {
                persistedDraft = draftToSave
            }
            return
        }
        AccountAssetStore.set(data, for: .businessCard, email: auth.currentEmail, namespace: assetNamespace)
        persistedDraft = draftToSave
        NotificationCenter.default.post(name: .accountAssetsDidChange, object: nil)
    }
}

private struct BusinessCardQRRow: View {
    @Environment(AppLanguageSettings.self) private var languageSettings
    @Binding var item: BusinessCardQR
    var onDelete: () -> Void
    var onImageLoaded: (Data) -> Void
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageLoadTask: Task<Void, Never>?
    @State private var isShowingPreview = false

    private func localized(_ key: String) -> String {
        BusinessCardCopy.text(key, language: languageSettings.selectedLanguage)
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = item.imageData, let image = UIImage(data: data) {
                    Button { isShowingPreview = true } label: {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(localized("二维码")): \(item.name)")
                } else {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localized("选择二维码图片"))
                }
            }
            .frame(width: 68, height: 68)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text(localized("二维码名称"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SystemIMETextField(text: $item.name, placeholder: localized("例如：微信"))
                    .padding(6)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .frame(minWidth: 0)
                    .layoutPriority(1)
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
                .navigationTitle(item.name.isEmpty ? localized("二维码") : item.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if let data = item.imageData, let image = UIImage(data: data) {
                            ShareLink(
                                item: Image(uiImage: image),
                                preview: SharePreview(item.name.isEmpty ? localized("二维码") : item.name, image: Image(uiImage: image))
                            ) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .accessibilityLabel(localized("分享二维码"))
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(localized("完成")) { isShowingPreview = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: pickerItem) { _, newValue in
            imageLoadTask?.cancel()
            imageLoadTask = nil
            guard let newValue else { return }
            imageLoadTask = Task {
                guard let data = try? await newValue.loadTransferable(type: Data.self),
                      !Task.isCancelled, pickerItem == newValue, UIImage(data: data) != nil else { return }
                onImageLoaded(data)
            }
        }
        .onDisappear { imageLoadTask?.cancel() }
    }
}

struct BusinessCardPreview: View {
    let name: String
    let phone: String
    let email: String
    let nickname: String
    let portraitData: Data?
    let qrCodeData: Data?
    let style: Int

    private var displayNickname: String {
        let value = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? BusinessCardCopy.text("请填写昵称", language: AppLanguage(rawValue: AppLanguageSettings.effectiveIdentifier) ?? .english) : value
    }

    private var isMetallic: Bool { style == 1 }
    private let gold = Color(red: 0.80, green: 0.65, blue: 0.34)

    var body: some View {
        Group {
            if isMetallic {
                metallicCard
            } else {
                classicCard
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var classicCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                portrait
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(isMetallic ? 0.45 : 0.7), lineWidth: 1))
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayNickname)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Rectangle().fill(.white.opacity(isMetallic ? 0.35 : 0.5)).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                Label(phone, systemImage: "phone.fill")
                Label(email, systemImage: "envelope.fill")
            }
            .font(.caption.weight(.medium))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(isMetallic ? Color.white : Color(red: 0.24, green: 0.20, blue: 0.16))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [Color.white, Color(red: 0.97, green: 0.93, blue: 0.86)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.accentColor.opacity(0.18), lineWidth: 1))
                .shadow(color: .brown.opacity(0.1), radius: 7, x: 0, y: 4)
        }
    }

    private var metallicCard: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(red: 0.055, green: 0.05, blue: 0.06))
                    GoldCardPanel()
                        .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.85, blue: 0.48), gold, Color(red: 0.52, green: 0.35, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    GoldCardAccent()
                        .fill(.white.opacity(0.12))
                    VStack(alignment: .leading, spacing: height * 0.07) {
                        HStack(spacing: 7) {
                            portrait
                                .frame(width: height * 0.22, height: height * 0.22)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 1))
                        }
                        Spacer(minLength: 0)
                        qrMark
                            .frame(width: height * 0.34, height: height * 0.34)
                    }
                    .foregroundStyle(Color.black.opacity(0.86))
                    .padding(.leading, height * 0.14)
                    .padding(.vertical, height * 0.11)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .frame(width: proxy.size.width * 0.32)

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Text(displayNickname)
                        .font(.system(size: height * 0.13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Rectangle().fill(gold.opacity(0.9)).frame(height: 1)
                        .padding(.vertical, height * 0.11)
                    VStack(alignment: .leading, spacing: height * 0.085) {
                        if !phone.isEmpty && phone != "Not provided" {
                            metallicContact(phone, icon: "phone.fill", height: height)
                        }
                        if !email.isEmpty && email != "Not provided" {
                            metallicContact(email, icon: "envelope.fill", height: height)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, height * 0.12)
                .padding(.vertical, height * 0.12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .background(Color(red: 0.055, green: 0.05, blue: 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(gold.opacity(0.65), lineWidth: 1))
            .shadow(color: .black.opacity(0.23), radius: 12, x: 0, y: 8)
        }
        .aspectRatio(1.72, contentMode: .fit)
    }

    private func metallicContact(_ value: String, icon: String, height: CGFloat) -> some View {
        HStack(spacing: height * 0.07) {
            Image(systemName: icon)
                .font(.system(size: height * 0.07, weight: .semibold))
                .foregroundStyle(Color(red: 0.12, green: 0.10, blue: 0.08))
                .frame(width: height * 0.17, height: height * 0.17)
                .background(LinearGradient(colors: [Color(red: 0.98, green: 0.84, blue: 0.44), gold], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 5))
            Text(value)
                .font(.system(size: height * 0.065, weight: .medium))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var qrMark: some View {
        if let qrCodeData, let image = UIImage(data: qrCodeData) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(4)
                .background(.white, in: RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "qrcode")
                .resizable()
                .scaledToFit()
                .padding(5)
                .foregroundStyle(.black.opacity(0.72))
                .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 4))
        }
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

private struct GoldCardPanel: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.width * 0.69, y: 0))
        path.addCurve(to: CGPoint(x: rect.width * 0.51, y: rect.height), control1: CGPoint(x: rect.width * 0.99, y: rect.height * 0.28), control2: CGPoint(x: rect.width * 0.26, y: rect.height * 0.70))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private struct GoldCardAccent: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.64, y: 0))
        path.addCurve(to: CGPoint(x: rect.width * 0.48, y: rect.height), control1: CGPoint(x: rect.width * 0.88, y: rect.height * 0.28), control2: CGPoint(x: rect.width * 0.16, y: rect.height * 0.67))
        path.addLine(to: CGPoint(x: rect.width * 0.53, y: rect.height))
        path.addCurve(to: CGPoint(x: rect.width * 0.69, y: 0), control1: CGPoint(x: rect.width * 0.34, y: rect.height * 0.63), control2: CGPoint(x: rect.width * 0.94, y: rect.height * 0.28))
        path.closeSubpath()
        return path
    }
}

private struct BusinessCardImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct BusinessCardShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
