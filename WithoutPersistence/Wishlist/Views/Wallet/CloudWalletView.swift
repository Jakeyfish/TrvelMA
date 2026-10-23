import SwiftUI
import PhotosUI
import UIKit
import Charts

private struct OnlinePaymentMethod: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var qrImageData: Data?
    var qrImagePath: String?
}

private struct OnlinePaymentMethodCollection: Codable {
    var methods: [OnlinePaymentMethod] = []
}

private struct CloudWalletCategory: Identifiable {
    let id: String
    let title: String
    let amount: Double
    let isExpense: Bool
    let color: Color
    var absoluteAmount: Double { abs(amount) }
}

private enum OnlineWalletPeriod: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: "天"
        case .week: "本周"
        case .month: "本月"
        case .year: "年"
        }
    }
}

struct CloudWalletView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.locale) private var locale
    @AppStorage(BaseCurrencyCatalog.countryCodeKey) private var baseCurrencyCountry = BaseCurrencyCatalog.defaultCountryCode
    @State private var tripsModel = CloudTripDirectoryModel()
    @State private var assets = CloudAccountAssetModel()
    @State private var period: OnlineWalletPeriod = .day
    @State private var anchorDate = Calendar.current.startOfDay(for: .now)
    @State private var methods: [OnlinePaymentMethod] = []
    @State private var savedMethods: [OnlinePaymentMethod] = []
    @State private var isLoaded = false
    @State private var loadGeneration = 0
    @State private var loadedEmail = ""
    @State private var paymentMethodsSaveTask: Task<Void, Never>?

    private var calendar: Calendar {
        var value = Calendar.current
        value.locale = locale
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }

    private var interval: DateInterval {
        switch period {
        case .day:
            let start = calendar.startOfDay(for: anchorDate)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400))
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: anchorDate)
                ?? DateInterval(start: calendar.startOfDay(for: anchorDate), duration: 7 * 86400)
        case .month:
            return calendar.dateInterval(of: .month, for: anchorDate)
                ?? DateInterval(start: calendar.startOfDay(for: anchorDate), duration: 31 * 86400)
        case .year:
            return calendar.dateInterval(of: .year, for: anchorDate)
                ?? DateInterval(start: calendar.startOfDay(for: anchorDate), duration: 366 * 86400)
        }
    }

    private var periodTrips: [CloudOnlineRepository.CloudTripRecord] {
        tripsModel.trips.filter { trip in
            guard let date = trip.appointmentDate.cloudDateValue else { return false }
            return date >= interval.start && date < interval.end
        }
    }

    private var totalsByCurrency: [(code: String, income: Double, expenses: Double)] {
        let groups = Dictionary(grouping: periodTrips, by: { $0.currencyCode.uppercased() })
        return groups.keys.sorted().compactMap { code in
            guard let records = groups[code] else { return nil }
            let incoming = records.reduce(0) { total, trip in
                total + max(0, trip.price) + max(0, trip.tip)
                    + trip.expenses.filter(\.isAddition).reduce(0) { $0 + abs($1.amount) }
            }
            let outgoing = records.reduce(0) { total, trip in
                total + trip.expenses.filter { !$0.isAddition }.reduce(0) { $0 + abs($1.amount) }
            }
            return (code, incoming, outgoing)
        }
    }

    private var financialCategories: [CloudWalletCategory] {
        var grouped: [String: (title: String, isExpense: Bool, amount: Double)] = [:]

        func add(_ key: String, title: String, isExpense: Bool, amount: Double) {
            guard amount > 0.0001 else { return }
            let prior = grouped[key]?.amount ?? 0
            grouped[key] = (title, isExpense, prior + amount)
        }

        for trip in periodTrips {
            add("__trip_income", title: localized("行程费用", "Trip fare", "Tarifa del viaje", "運賃", "운행 요금"), isExpense: false, amount: max(0, trip.price))
            add("__tip_income", title: localized("小费", "Tips", "Propinas", "チップ", "팁"), isExpense: false, amount: max(0, trip.tip))
            for expense in trip.expenses {
                let title = expense.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle = title.isEmpty ? localized("其他", "Other", "Otros", "その他", "기타") : title
                add("\(!expense.isAddition ? "expense" : "income")|\(displayTitle)", title: displayTitle,
                    isExpense: !expense.isAddition,
                    amount: abs(expense.amount))
            }
        }

        let palette: [Color] = [
            Color(red: 0.31, green: 0.49, blue: 0.96), Color(red: 0.18, green: 0.73, blue: 0.62),
            Color(red: 0.98, green: 0.66, blue: 0.26), Color(red: 0.66, green: 0.42, blue: 0.91),
            Color(red: 0.95, green: 0.39, blue: 0.47), Color(red: 0.25, green: 0.69, blue: 0.84),
            Color(red: 0.76, green: 0.60, blue: 0.27)
        ]
        return grouped.map { key, value in
            let colorIndex = abs(key.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }) % palette.count
            let baseColor = palette[colorIndex]
            return CloudWalletCategory(id: key, title: value.title,
                                       amount: value.amount, isExpense: value.isExpense,
                                       color: value.isExpense ? baseColor.opacity(0.78) : baseColor)
        }.sorted {
            if $0.isExpense != $1.isExpense { return !$0.isExpense }
            return $0.amount > $1.amount
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    periodPicker
                    dateNavigator
                    financialSummary
                    financialDetails
                    paymentMethodsSection
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("钱包")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: methods) { _, updatedMethods in
                guard isLoaded, updatedMethods != savedMethods else { return }
                paymentMethodsSaveTask?.cancel()
                paymentMethodsSaveTask = Task {
                    do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
                    guard !Task.isCancelled else { return }
                    while assets.isSaving {
                        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                        guard !Task.isCancelled else { return }
                    }
                    await savePaymentMethods()
                }
            }
            .task(id: "\(auth.currentEmail)|\(auth.serverEntitlement?.edition.rawValue ?? "")") {
                paymentMethodsSaveTask?.cancel()
                tripsModel.clearForAccountChange()
                assets.beginAccountChange()
                methods = []
                savedMethods = []
                loadedEmail = ""
                isLoaded = false
                await load()
            }
            .alert("钱包数据载入失败", isPresented: Binding(
                get: { assets.errorMessage != nil || tripsModel.errorMessage != nil },
                set: { if !$0 { assets.clearError(); tripsModel.clearError() } }
            )) {
                Button("重试") { Task { await load() } }
                Button("关闭", role: .cancel) { assets.clearError(); tripsModel.clearError() }
            } message: {
                Text(assets.errorMessage ?? tripsModel.errorMessage ?? "")
            }
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 5) {
            ForEach(OnlineWalletPeriod.allCases) { option in
                Button {
                    period = option
                    anchorDate = Calendar.current.startOfDay(for: .now)
                } label: {
                    Text(LocalizedStringKey(option.title))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(period == option ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(period == option ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var dateNavigator: some View {
        HStack(spacing: 14) {
            Button { moveDate(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .accessibilityLabel("上一段日期")
            Spacer()
            Group {
                if period == .week {
                    VStack(spacing: 1) {
                        Text(weekYearTitle).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        Text(weekDateTitle).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    }
                } else {
                    Text(dateTitle).font(.system(size: 16, weight: .semibold)).monospacedDigit()
                }
            }
            Spacer()
            Button { moveDate(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .accessibilityLabel("下一段日期")
        }
        .buttonStyle(.plain)
    }

    private var dateTitle: String {
        switch period {
        case .day: anchorDate.formatted(.dateTime.year().month(.wide).day().locale(locale))
        case .week: weekDateTitle
        case .month: interval.start.formatted(.dateTime.year().month(.wide).locale(locale))
        case .year: interval.start.formatted(.dateTime.year().locale(locale))
        }
    }

    private var weekDateTitle: String {
        let first = interval.start
        let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\(first.formatted(.dateTime.month(.abbreviated).day().locale(locale))) – \(last.formatted(.dateTime.month(.abbreviated).day().locale(locale)))"
    }

    private var weekYearTitle: String {
        let firstYear = interval.start.formatted(.dateTime.year().locale(locale))
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let lastYear = lastDay.formatted(.dateTime.year().locale(locale))
        return firstYear == lastYear ? firstYear : "\(firstYear) – \(lastYear)"
    }

    private var financialSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                chartLayer(isDepth: true).offset(y: 8)
                chartLayer(isDepth: false)
                VStack(spacing: 5) {
                    Text("总收入").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    Text(centerTotal(income: true)).font(.system(size: 11, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 42, height: 1)
                    Text("净收入").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    Text(centerTotal(income: false)).font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(netIncome >= 0 ? Color.primary : Color.red).minimumScaleFactor(0.6).lineLimit(1)
                }
                .padding(.horizontal, 8)
            }
            .frame(width: 190, height: 204)
            .accessibilityElement(children: .combine)

            if tripsModel.isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if financialCategories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("暂无收支").font(.system(size: 13, weight: .semibold))
                    Text("所选日期内没有财务记录").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(financialCategories) { category in categoryRow(category) }
                    }.padding(.vertical, 5)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: 184, alignment: .topLeading)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }

    @ViewBuilder
    private func chartLayer(isDepth: Bool) -> some View {
        if financialCategories.isEmpty || totalVolume <= 0 {
            Circle().stroke(Color.secondary.opacity(isDepth ? 0.16 : 0.12), lineWidth: 24).padding(20)
        } else {
            Chart {
                ForEach(financialCategories) { category in
                    SectorMark(angle: .value("Amount", category.absoluteAmount), innerRadius: .ratio(0.65), angularInset: 1.5)
                        .foregroundStyle(isDepth ? category.color.opacity(0.48) : category.color)
                        .cornerRadius(3)
                }
            }
            .chartLegend(.hidden).chartXAxis(.hidden).chartYAxis(.hidden).padding(4)
        }
    }

    private var totalVolume: Double { financialCategories.reduce(0) { $0 + $1.absoluteAmount } }
    private var netIncome: Double { totalsByCurrency.reduce(0) { $0 + $1.income - $1.expenses } }
    private var totalIncome: Double { totalsByCurrency.reduce(0) { $0 + $1.income } }
    private var totalExpense: Double { totalsByCurrency.reduce(0) { $0 + $1.expenses } }
    private var currencyCountryCode: String {
        BaseCurrencyCatalog.options.first { $0.currencyCode == tripsModel.currencyCode.uppercased() }?.countryCode
            ?? baseCurrencyCountry
    }

    private func centerTotal(income: Bool) -> String {
        BaseCurrencyCatalog.format(income ? totalIncome : netIncome, countryCode: currencyCountryCode)
    }

    private func localized(_ chinese: String, _ english: String, _ spanish: String, _ japanese: String, _ korean: String) -> String {
        switch locale.language.languageCode?.identifier {
        case "en": return english
        case "es": return spanish
        case "ja": return japanese
        case "ko": return korean
        case "zh":
            if locale.identifier.contains("Hant") || locale.identifier.contains("TW") || locale.identifier.contains("HK") {
                return ["行程费用": "行程費用", "小费": "小費", "条行程": "筆行程"][chinese] ?? chinese
            }
            return chinese
        default: return chinese
        }
    }

    private func categoryRow(_ category: CloudWalletCategory) -> some View {
        let percentage = totalVolume > 0 ? category.absoluteAmount / totalVolume * 100 : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(category.color).frame(width: 8, height: 8)
                Text(category.title).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: "%.1f%%", percentage)).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(spacing: 4) {
                Text(category.isExpense ? "−" : "+").foregroundStyle(category.isExpense ? Color.orange : Color.green)
                Text(BaseCurrencyCatalog.format(category.absoluteAmount, countryCode: currencyCountryCode)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded)).padding(.leading, 14)
        }.accessibilityElement(children: .combine)
    }

    private var financialDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("收支明细", systemImage: "chart.pie.fill").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(periodTrips.count) \(localized("条行程", "trips", "viajes", "件の行程", "개 일정"))")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                summaryPill(
                    title: "收入",
                    amountText: BaseCurrencyCatalog.format(totalIncome, countryCode: currencyCountryCode),
                    icon: "arrow.down.left", color: .green
                )
                summaryPill(
                    title: "支出",
                    amountText: BaseCurrencyCatalog.format(totalExpense, countryCode: currencyCountryCode),
                    icon: "arrow.up.right", color: .orange
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func summaryPill(title: String, amountText: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(LocalizedStringKey(title), systemImage: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(color)
            Text(amountText).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
    }

    private var paymentMethodsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("收款方式", systemImage: "qrcode")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { methods.append(OnlinePaymentMethod()) } label: {
                    Label("添加", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                    .buttonStyle(.bordered)
            }
            if methods.isEmpty {
                Text("添加收款方式名称和二维码，方便向客户展示。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach($methods) { $method in
                    OnlinePaymentMethodRow(method: $method, locale: locale) {
                        methods.removeAll { $0.id == method.id }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func walletAmountTile(_ title: String, amount: Double, code: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(color)
            Text(walletCurrency(amount, code: code)).font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
    }

    private func moveDate(_ offset: Int) {
        let component: Calendar.Component = switch period {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        anchorDate = calendar.date(byAdding: component, value: offset, to: anchorDate) ?? anchorDate
    }

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let email = auth.currentEmail
        let edition = auth.serverEntitlement?.edition
        isLoaded = false
        await tripsModel.reloadTrips(using: auth)
        guard loadGeneration == generation,
              auth.currentEmail.caseInsensitiveCompare(email) == .orderedSame,
              auth.serverEntitlement?.edition == edition else { return }
        guard let data = await assets.load(.paymentMethods, using: auth) else {
            guard loadGeneration == generation,
                  auth.currentEmail.caseInsensitiveCompare(email) == .orderedSame,
                  auth.serverEntitlement?.edition == edition else { return }
            if assets.errorMessage == nil {
                methods = []
                savedMethods = []
                loadedEmail = email
                isLoaded = true
            }
            return
        }
        guard loadGeneration == generation,
              auth.currentEmail.caseInsensitiveCompare(email) == .orderedSame,
              auth.serverEntitlement?.edition == edition else { return }
        guard let saved = try? JSONDecoder().decode(OnlinePaymentMethodCollection.self, from: data) else {
            assets.setLoadError("收款方式资料格式无效，未覆盖云端原资料。")
            return
        }
        methods = saved.methods
        savedMethods = methods
        loadedEmail = email
        isLoaded = true
    }

    private func savePaymentMethods() async {
        guard isLoaded, loadedEmail.caseInsensitiveCompare(auth.currentEmail) == .orderedSame,
              methods != savedMethods else { return }
        let methodsToSave = methods
        guard let data = try? JSONEncoder().encode(OnlinePaymentMethodCollection(methods: methodsToSave)) else { return }
        let email = auth.currentEmail
        guard await assets.save(data, as: .paymentMethods, using: auth) else { return }
        guard auth.currentEmail.caseInsensitiveCompare(email) == .orderedSame else { return }
        savedMethods = methodsToSave
    }
}

private struct OnlinePaymentMethodRow: View {
    @Binding var method: OnlinePaymentMethod
    let locale: Locale
    let onDelete: () -> Void
    @State private var pickerItem: PhotosPickerItem?
    @State private var isPreviewing = false
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            qrImageControl
                .frame(width: 82, height: 82)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(localized("收款方式名称", "Payment method name", "Nombre del método de pago", "支払い方法名", "결제 방법 이름"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(localized("例如：微信、Venmo", "e.g. PayPal, Venmo", "p. ej., PayPal, Venmo", "例：PayPay", "예: PayPal, Venmo"), text: $method.name)
                    .font(.system(size: 15, weight: .medium))
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { isNameFieldFocused = false }
                    .keyboardDoneToolbar()
                Text(method.qrImageData == nil
                     ? localized("添加收款二维码", "Add a payment QR code", "Añadir un código QR de pago", "支払い用QRコードを追加", "결제 QR 코드 추가")
                     : localized("点击二维码可直接查看", "Tap the QR code to preview", "Toca el código QR para verlo", "QRコードをタップして表示", "QR 코드를 눌러 미리보기"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 38)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .accessibilityLabel(localized("删除收款方式", "Delete payment method", "Eliminar método de pago", "支払い方法を削除", "결제 방법 삭제"))
        }
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil {
                    method.qrImageData = data
                }
                pickerItem = nil
            }
        }
        .sheet(isPresented: $isPreviewing) {
            NavigationStack {
                Group {
                    if let data = method.qrImageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.systemBackground))
                    }
                }
                .navigationTitle(method.name.isEmpty ? localized("收款二维码", "Payment QR code", "Código QR de pago", "支払い用QRコード", "결제 QR 코드") : method.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(localized("完成", "Done", "Listo", "完了", "완료")) { isPreviewing = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var qrImageControl: some View {
        if let data = method.qrImageData, let image = UIImage(data: data) {
            Button { isPreviewing = true } label: {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("查看收款二维码", "View payment QR code", "Ver código QR de pago", "支払い用QRコードを表示", "결제 QR 코드 보기"))
        } else {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                VStack(spacing: 5) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 25, weight: .medium))
                    Text(localized("选择图片", "Choose image", "Elegir imagen", "画像を選択", "이미지 선택"))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func localized(_ chinese: String, _ english: String, _ spanish: String, _ japanese: String, _ korean: String) -> String {
        switch locale.language.languageCode?.identifier {
        case "en": return english
        case "es": return spanish
        case "ja": return japanese
        case "ko": return korean
        case "zh":
            if locale.identifier.contains("Hant") || locale.identifier.contains("TW") || locale.identifier.contains("HK") {
                let traditional: [String: String] = [
                    "收款方式名称": "收款方式名稱",
                    "例如：微信、Venmo": "例如：微信、Venmo",
                    "添加收款二维码": "新增收款二維碼",
                    "点击二维码可直接查看": "點擊二維碼可直接檢視",
                    "删除收款方式": "刪除收款方式",
                    "收款二维码": "收款二維碼",
                    "选择图片": "選擇圖片",
                    "查看收款二维码": "檢視收款二維碼",
                    "完成": "完成"
                ]
                return traditional[chinese] ?? chinese
            }
            return chinese
        default: return chinese
        }
    }
}

private func walletCurrency(_ amount: Double, code: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    return formatter.string(from: NSNumber(value: amount)) ?? "\(code) \(amount)"
}

private extension String {
    var cloudDateValue: Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: self) ?? ISO8601DateFormatter().date(from: self)
    }
}
