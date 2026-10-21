import SwiftUI
import SwiftData
import Charts
import PhotosUI
import UIKit

private struct WalletPaymentMethod: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = ""
    var qrImageData: Data?
}

private struct WalletPaymentMethodDraft: Codable {
    var methods: [WalletPaymentMethod] = []
}

private enum WalletPeriod: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }
}

private struct WalletCategory: Identifiable {
    let id: String
    let title: String
    let amount: Double
    let isExpense: Bool
    let color: Color

    var absoluteAmount: Double { abs(amount) }
}

struct WalletView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.locale) private var locale
    @Query private var bookings: [TripBookingRecord]
    @AppStorage(BaseCurrencyCatalog.countryCodeKey)
    private var baseCurrencyCountry = BaseCurrencyCatalog.defaultCountryCode

    @State private var period: WalletPeriod = .day
    @State private var anchorDate = Calendar.current.startOfDay(for: .now)
    @State private var paymentMethods: [WalletPaymentMethod] = []
    @State private var persistedPaymentMethods: [WalletPaymentMethod]?
    @State private var hasLoadedPaymentMethods = false

    init() {
        let scope = DataOwnership.activeScope
        _bookings = Query(filter: #Predicate { $0.ownerScope == scope })
    }

    private var paymentMethodsNamespace: AccountAssetStore.Namespace { auth.isCloudAccount ? .cloud : .local }

    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = locale
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private var dateInterval: DateInterval {
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

    private var periodBookings: [TripBookingRecord] {
        bookings.filter { $0.appointmentDate >= dateInterval.start && $0.appointmentDate < dateInterval.end }
    }

    private var categories: [WalletCategory] {
        var amounts: [String: (title: String, expense: Bool, amount: Double)] = [:]
        let tripFare = periodBookings.reduce(0) { $0 + max(0, $1.price) }
        let tips = periodBookings.reduce(0) { $0 + max(0, $1.tip) }
        if tripFare > 0 {
            amounts["__trip_income"] = (localized("行程费用", "Trip fare", "Tarifa del viaje", "運賃", "운행 요금"), false, tripFare)
        }
        if tips > 0 {
            amounts["__tip_income"] = (localized("小费", "Tips", "Propinas", "チップ", "팁"), false, tips)
        }

        for booking in periodBookings {
            for item in booking.expenseAdjustments where abs(item.amount) > 0.0001 {
                let expense = !item.isAddition
                let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? localized("其他", "Other", "Otros", "その他", "기타")
                    : item.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = "\(expense ? "expense" : "income")|\(title)"
                let prior = amounts[key]?.amount ?? 0
                amounts[key] = (title, expense, prior + abs(item.amount))
            }
        }

        let palette: [Color] = [
            Color(red: 0.31, green: 0.49, blue: 0.96),
            Color(red: 0.18, green: 0.73, blue: 0.62),
            Color(red: 0.98, green: 0.66, blue: 0.26),
            Color(red: 0.66, green: 0.42, blue: 0.91),
            Color(red: 0.95, green: 0.39, blue: 0.47),
            Color(red: 0.25, green: 0.69, blue: 0.84),
            Color(red: 0.76, green: 0.60, blue: 0.27)
        ]
        return amounts
            .map { key, value in
                WalletCategory(
                    id: key,
                    title: value.title,
                    amount: value.amount,
                    isExpense: value.expense,
                    color: value.expense ? paletteColor(for: key, palette: palette).opacity(0.78) : paletteColor(for: key, palette: palette)
                )
            }
            .sorted {
                if $0.isExpense != $1.isExpense { return !$0.isExpense }
                return $0.absoluteAmount > $1.absoluteAmount
            }
    }

    private var totalIncome: Double {
        periodBookings.reduce(0) { total, booking in
            total + max(0, booking.price) + max(0, booking.tip)
                + booking.expenseAdjustments.filter(\.isAddition).reduce(0) { $0 + abs($1.amount) }
        }
    }

    private var totalExpense: Double {
        periodBookings.reduce(0) { total, booking in
            total + booking.expenseAdjustments.filter { !$0.isAddition }.reduce(0) { $0 + abs($1.amount) }
        }
    }

    private var netIncome: Double { totalIncome - totalExpense }
    private var totalVolume: Double { categories.reduce(0) { $0 + $1.absoluteAmount } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    periodPicker
                    dateNavigator
                    financialSummary
                    categoryList
                    paymentMethodsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(localized("钱包", "Wallet", "Cartera", "ウォレット", "지갑"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: loadPaymentMethods)
            .onChange(of: paymentMethods) { _, _ in
                if paymentMethods != persistedPaymentMethods { savePaymentMethods() }
            }
            .onChange(of: auth.currentEmail) { _, _ in loadPaymentMethods() }
            .onChange(of: auth.isCloudAccount) { _, _ in loadPaymentMethods() }
            .onReceive(NotificationCenter.default.publisher(for: .accountAssetsDidSync)) { _ in loadPaymentMethods() }
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 5) {
            ForEach(WalletPeriod.allCases) { option in
                Button {
                    period = option
                    anchorDate = Calendar.current.startOfDay(for: .now)
                } label: {
                    Text(periodTitle(option))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(period == option ? Color.accentColor : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(period == option ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var dateNavigator: some View {
        HStack(spacing: 14) {
            Button { shiftPeriod(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("上一段日期", "Previous period", "Periodo anterior", "前の期間", "이전 기간"))

            Group {
                if period == .week {
                    VStack(spacing: 1) {
                        Text(weekYearTitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(weekDateTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                    }
                    .contentTransition(.numericText())
                } else {
                    Text(periodDateTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity)

            Button { shiftPeriod(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("下一段日期", "Next period", "Periodo siguiente", "次の期間", "다음 기간"))
        }
        .foregroundStyle(.primary)
    }

    private var periodDateTitle: String {
        return switch period {
        case .day:
            anchorDate.formatted(.dateTime.year().month(.wide).day().locale(locale))
        case .week: weekDateTitle
        case .month:
            dateInterval.start.formatted(.dateTime.year().month(.wide).locale(locale))
        case .year:
            dateInterval.start.formatted(.dateTime.year().locale(locale))
        }
    }

    private var weekDateTitle: String {
        let first = dateInterval.start
        let last = calendar.date(byAdding: .day, value: -1, to: dateInterval.end) ?? dateInterval.end
        return "\(first.formatted(.dateTime.month(.abbreviated).day().locale(locale))) – \(last.formatted(.dateTime.month(.abbreviated).day().locale(locale)))"
    }

    private var weekYearTitle: String {
        let firstYear = dateInterval.start.formatted(.dateTime.year().locale(locale))
        let lastDay = calendar.date(byAdding: .day, value: -1, to: dateInterval.end) ?? dateInterval.end
        let lastYear = lastDay.formatted(.dateTime.year().locale(locale))
        return firstYear == lastYear ? firstYear : "\(firstYear) – \(lastYear)"
    }

    private var financialSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                chartLayer(isDepth: true)
                    .offset(y: 8)
                chartLayer(isDepth: false)
                VStack(spacing: 5) {
                    Text(localized("总收入", "Income", "Ingresos", "総収入", "총수입"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(BaseCurrencyCatalog.format(totalIncome, countryCode: baseCurrencyCountry))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 42, height: 1)
                    Text(localized("净收入", "Net", "Neto", "純収入", "순수입"))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(BaseCurrencyCatalog.format(netIncome, countryCode: baseCurrencyCountry))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(netIncome >= 0 ? Color.primary : Color.red)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
            }
            .frame(width: 190, height: 204)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(localized("总收入", "Income", "Ingresos", "総収入", "총수입")) \(BaseCurrencyCatalog.format(totalIncome, countryCode: baseCurrencyCountry)), \(localized("净收入", "Net", "Neto", "純収入", "순수입")) \(BaseCurrencyCatalog.format(netIncome, countryCode: baseCurrencyCountry))")

            if categories.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("暂无收支", "No income or expenses", "Sin ingresos ni gastos", "収支データなし", "수입·지출 없음"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(localized("所选日期内没有财务记录", "No financial records for this period", "No hay registros financieros en este periodo", "この期間の財務記録はありません", "선택한 기간에 재무 기록이 없습니다"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(categories) { category in
                            categoryRow(category)
                        }
                    }
                    .padding(.vertical, 5)
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
        if categories.isEmpty || totalVolume <= 0 {
            Circle()
                .stroke(Color.secondary.opacity(isDepth ? 0.16 : 0.12), lineWidth: 24)
                .padding(20)
        } else {
            Chart {
                ForEach(categories) { item in
                    SectorMark(
                        angle: .value("Amount", item.absoluteAmount),
                        innerRadius: .ratio(0.65),
                        angularInset: 1.5
                    )
                    .foregroundStyle(isDepth ? item.color.opacity(0.48) : item.color)
                    .cornerRadius(3)
                }
            }
            .chartLegend(.hidden)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .padding(4)
        }
    }

    private func categoryRow(_ category: WalletCategory) -> some View {
        let percentage = totalVolume > 0 ? category.absoluteAmount / totalVolume * 100 : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(category.color).frame(width: 8, height: 8)
                Text(category.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: "%.1f%%", percentage))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                Text(category.isExpense ? "−" : "+")
                    .foregroundStyle(category.isExpense ? Color.orange : Color.green)
                Text(BaseCurrencyCatalog.format(category.absoluteAmount, countryCode: baseCurrencyCountry))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.leading, 14)
        }
        .accessibilityElement(children: .combine)
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(localized("收支明细", "Breakdown", "Desglose", "収支内訳", "수입·지출 내역"), systemImage: "chart.pie.fill")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(periodBookings.count) \(localized("条行程", "trips", "viajes", "件の行程", "개 일정"))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                summaryPill(
                    title: localized("收入", "Income", "Ingresos", "収入", "수입"),
                    amount: totalIncome,
                    icon: "arrow.down.left",
                    color: .green
                )
                summaryPill(
                    title: localized("支出", "Expenses", "Gastos", "支出", "지출"),
                    amount: totalExpense,
                    icon: "arrow.up.right",
                    color: .orange
                )
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var paymentMethodsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(localized("收款方式", "Payment methods", "Métodos de pago", "お支払い方法", "결제 방법"), systemImage: "qrcode")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        paymentMethods.append(WalletPaymentMethod())
                    }
                } label: {
                    Label(localized("添加", "Add", "Añadir", "追加", "추가"), systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }

            if paymentMethods.isEmpty {
                Text(localized("添加收款方式名称和二维码，方便向客户展示。", "Add a payment method name and QR code to show customers.", "Añade un método de pago y un código QR para mostrarlos a tus clientes.", "お客様に表示する支払い方法とQRコードを追加します。", "고객에게 표시할 결제 방법과 QR 코드를 추가하세요."))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach($paymentMethods) { $method in
                    WalletPaymentMethodRow(method: $method, locale: locale) {
                        withAnimation(.snappy(duration: 0.2)) {
                            paymentMethods.removeAll { $0.id == method.id }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func loadPaymentMethods() {
        guard !auth.currentEmail.isEmpty else {
            paymentMethods = []
            persistedPaymentMethods = []
            hasLoadedPaymentMethods = false
            return
        }
        if !auth.isCloudAccount {
            AccountAssetStore.migrateLegacyAssetsToLocal(email: auth.currentEmail)
        }
        if let data = AccountAssetStore.data(for: .paymentMethods, email: auth.currentEmail, namespace: paymentMethodsNamespace),
           let saved = try? JSONDecoder().decode(WalletPaymentMethodDraft.self, from: data) {
            paymentMethods = saved.methods
        } else {
            paymentMethods = []
        }
        persistedPaymentMethods = paymentMethods
        hasLoadedPaymentMethods = true
    }

    private func savePaymentMethods() {
        guard hasLoadedPaymentMethods,
              !auth.currentEmail.isEmpty,
              let data = try? JSONEncoder().encode(WalletPaymentMethodDraft(methods: paymentMethods)) else { return }
        AccountAssetStore.set(data, for: .paymentMethods, email: auth.currentEmail, namespace: paymentMethodsNamespace)
        persistedPaymentMethods = paymentMethods
        NotificationCenter.default.post(name: .accountAssetsDidChange, object: nil)
    }

    private func summaryPill(title: String, amount: Double, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
            Text(BaseCurrencyCatalog.format(amount, countryCode: baseCurrencyCountry))
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private func periodTitle(_ option: WalletPeriod) -> String {
        return switch option {
        case .day: localized("天", "Day", "Día", "日", "일")
        case .week: localized("本周", "Week", "Semana", "週", "주")
        case .month: localized("本月", "Month", "Mes", "月", "월")
        case .year: localized("年", "Year", "Año", "年", "년")
        }
    }

    private func localized(_ chinese: String, _ english: String, _ spanish: String, _ japanese: String, _ korean: String) -> String {
        return switch locale.language.languageCode?.identifier {
        case "en": english
        case "es": spanish
        case "ja": japanese
        case "ko": korean
        case "zh": isTraditionalChinese ? traditionalChinese(chinese) : chinese
        default: chinese
        }
    }

    private var isTraditionalChinese: Bool {
        locale.identifier.contains("Hant") || locale.identifier.contains("TW") || locale.identifier.contains("HK")
    }

    private func traditionalChinese(_ text: String) -> String {
        let translations: [String: String] = [
            "钱包": "錢包", "行程费用": "行程費用", "小费": "小費", "其他": "其他",
            "上一段日期": "上一段日期", "下一段日期": "下一段日期", "总收入": "總收入", "净收入": "淨收入",
            "暂无收支": "暫無收支", "所选日期内没有财务记录": "所選日期內沒有財務記錄",
            "收支明细": "收支明細", "条行程": "筆行程", "收入": "收入", "支出": "支出",
            "收款方式": "收款方式", "添加": "新增",
            "天": "日", "本周": "本週", "本月": "本月", "年": "年"
        ]
        return translations[text] ?? text
    }

    private func paletteColor(for key: String, palette: [Color]) -> Color {
        let index = abs(key.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }) % palette.count
        return palette[index]
    }

    private func shiftPeriod(by value: Int) {
        let component: Calendar.Component
        switch period {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        withAnimation(.snappy(duration: 0.22)) {
            anchorDate = calendar.date(byAdding: component, value: value, to: anchorDate) ?? anchorDate
        }
    }
}

private struct WalletPaymentMethodRow: View {
    @Binding var method: WalletPaymentMethod
    let locale: Locale
    let onDelete: () -> Void
    @State private var pickerItem: PhotosPickerItem?
    @State private var isShowingQRPreview = false
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
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                guard let data = try? await newValue.loadTransferable(type: Data.self),
                      UIImage(data: data) != nil else { return }
                method.qrImageData = data
                pickerItem = nil
            }
        }
        .sheet(isPresented: $isShowingQRPreview) {
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
                        Button(localized("完成", "Done", "Listo", "完了", "완료")) { isShowingQRPreview = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private var qrImageControl: some View {
        if let data = method.qrImageData, let image = UIImage(data: data) {
            Button { isShowingQRPreview = true } label: {
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
