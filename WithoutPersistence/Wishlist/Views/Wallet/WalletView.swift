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
    let incomeAmount: Double
    let expenseAmount: Double
    let color: Color

    var absoluteAmount: Double { abs(amount) }
}

struct WalletView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.locale) private var locale
    @Query private var bookings: [TripBookingRecord]
    @AppStorage(BaseCurrencyCatalog.countryCodeKey)
    private var baseCurrencyCountry = BaseCurrencyCatalog.defaultCountryCode

    @State private var tripSnapshot: FinancialTripSnapshotCollection?
    @State private var period: WalletPeriod = .day
    @State private var anchorDate = Calendar.current.startOfDay(for: .now)
    @State private var paymentMethods: [WalletPaymentMethod] = []
    @State private var persistedPaymentMethods: [WalletPaymentMethod]?
    @State private var hasLoadedPaymentMethods = false

    init() {
        let scope = DataOwnership.activeScope
        _bookings = Query(filter: #Predicate { $0.ownerScope == scope })
    }

    private var agencyStatementRows: [AgencyStatementRow] {
        bookings.filter { $0.orderSource == "旅行社订单" && !$0.isPaid && !$0.isCancelled }.map { t in
            AgencyStatementRow(id: t.id.uuidString, agencyCode: t.travelAgencyCode, agencyName: t.travelAgencyName,
                date: t.appointmentDate, time: t.appointmentTime, order: t.travelAgencyOrderNumber,
                service: t.serviceType, guest: t.customerName, contact: t.customerContact,
                route: ([t.locationStart] + t.locationStops + [t.locationEnd]).joined(separator: " → "),
                memo: t.memo, passengers: t.customerCount, fare: t.price, tip: t.tip,
                currency: BaseCurrencyCatalog.options.first { $0.countryCode == baseCurrencyCountry }?.currencyCode ?? "USD",
                fees: t.expenseAdjustments.map { .init(title: $0.title, amount: $0.amount, addition: $0.isAddition) })
        }
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
        bookings.filter { FinancialTripInclusion.includes(cancelled: $0.isCancelled, date: $0.appointmentDate, in: dateInterval) }
    }

    private var categories: [WalletCategory] {
        var entries: [FinancialCategoryAggregation.Entry] = []
        for trip in periodBookings {
            entries.append(.init(title: localized("行程费用", "Trip fare", "Tarifa del viaje", "運賃", "운행 요금"), amount: max(0, trip.price), isAddition: true))
            entries.append(.init(title: localized("小费", "Tips", "Propinas", "チップ", "팁"), amount: max(0, trip.tip), isAddition: true))
            entries += trip.expenseAdjustments.map { .init(title: $0.title, amount: $0.amount, isAddition: $0.isAddition) }
        }
        let palette: [Color] = [
            Color(red: 0.31, green: 0.49, blue: 0.96), Color(red: 0.18, green: 0.73, blue: 0.62),
            Color(red: 0.98, green: 0.66, blue: 0.26), Color(red: 0.66, green: 0.42, blue: 0.91),
            Color(red: 0.95, green: 0.39, blue: 0.47), Color(red: 0.25, green: 0.69, blue: 0.84),
            Color(red: 0.76, green: 0.60, blue: 0.27)
        ]
        return FinancialCategoryAggregation.groups(entries, fallback: localized("其他", "Other", "Otros", "その他", "기타")).map { group in
            let index = group.id.unicodeScalars.reduce(0) { ($0 &* 31) &+ UInt($1.value) } % UInt(palette.count)
            return WalletCategory(id: group.id, title: group.title, amount: group.amount, isExpense: group.isExpense,
                incomeAmount: group.income, expenseAmount: group.expense,
                color: group.isExpense ? palette[Int(index)].opacity(0.78) : palette[Int(index)])
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
        Group {
            if auth.serverEntitlement?.edition == .cloud {
                CloudWalletView()
            } else {
                localWalletPage
            }
        }
    }

    private var localWalletPage: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    periodPicker
                    dateNavigator
                    financialSummary
                    categoryList
                    paymentMethodsSection
                    AgencyStatementSection(rows: agencyStatementRows).id(auth.currentEmail)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text(localized("财务", "Finance", "Finanzas", "財務", "재무")).font(.system(size: 30, weight: .bold, design: .rounded))
                    Spacer()
                }.frame(minHeight: 52).padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Color(.systemGroupedBackground))
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $tripSnapshot) { snapshot in
                FinancialTripSnapshotSheet(snapshot: snapshot)
            }
            .onChange(of: auth.currentEmail) { _, _ in tripSnapshot = nil }
            .onAppear(perform: loadPaymentMethods)
            .onChange(of: paymentMethods) { _, _ in
                if paymentMethods != persistedPaymentMethods { savePaymentMethods() }
            }
            .onChange(of: auth.currentEmail) { _, _ in loadPaymentMethods() }
            .onChange(of: auth.isCloudAccount) { _, _ in loadPaymentMethods() }
            .onReceive(NotificationCenter.default.publisher(for: .accountAssetsDidSync)) { _ in loadPaymentMethods() }
            .onReceive(NotificationCenter.default.publisher(for: .accountScopedLocalDataDidClear)) { notification in
                guard (notification.object as? String) == DataOwnership.activeScope else { return }
                loadPaymentMethods()
            }
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
            VStack(alignment: .leading, spacing: 2) {
                if category.incomeAmount > 0 {
                    Text("+" + BaseCurrencyCatalog.format(category.incomeAmount, countryCode: baseCurrencyCountry))
                        .foregroundStyle(Color.green)
                }
                if category.expenseAmount > 0 {
                    Text("−" + BaseCurrencyCatalog.format(category.expenseAmount, countryCode: baseCurrencyCountry))
                        .foregroundStyle(Color.orange)
                }
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.leading, 14)
        }
        .accessibilityElement(children: .combine)
    }

    private var snapshotRows: [FinancialTripSnapshotRow] {
        periodBookings.map { trip in
            FinancialTripSnapshotRow(id: trip.id.uuidString, date: trip.appointmentDate,
                time: trip.appointmentTime, guest: trip.customerName,
                amount: BaseCurrencyCatalog.format(trip.price + trip.tip + trip.expenseAdjustments.reduce(0) { $0 + ($1.isAddition ? abs($1.amount) : -abs($1.amount)) }, countryCode: baseCurrencyCountry),
                details: FinancialTripSnapshotRow.details(service: trip.serviceType, start: trip.locationStart,
                    stops: trip.locationStops, end: trip.locationEnd, flight: trip.flightInfo,
                    completed: trip.isCompleted, cancelled: trip.isCancelled, paid: trip.isPaid,
                    contact: trip.customerContact, passengers: trip.customerCount, luggage: trip.customerStuff,
                    agency: trip.orderSource == "旅行社订单" ? trip.travelAgencyName : "", order: trip.orderSource == "旅行社订单" ? trip.travelAgencyOrderNumber : "", memo: trip.memo)
                    + [("小费", BaseCurrencyCatalog.format(trip.tip, countryCode: baseCurrencyCountry))]
                    + trip.expenseAdjustments.map { ($0.title, "\($0.isAddition ? "+" : "−")\(BaseCurrencyCatalog.format(abs($0.amount), countryCode: baseCurrencyCountry))") }, flightResult: (try? JSONDecoder().decode(SavedFlightSelection.self, from: Data(trip.flightSelectionSnapshotJSON.utf8)))?.selected)
        }.sorted { $0.date == $1.date ? ($0.time == $1.time ? $0.id < $1.id : $0.time < $1.time) : $0.date < $1.date }
    }

    private var categoryList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(localized("收支明细", "Breakdown", "Desglose", "収支内訳", "수입·지출 내역"), systemImage: "chart.pie.fill")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(periodBookings.count) \(localized("条行程", "trips", "viajes", "件の行程", "개 일정"))")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Button {
                        tripSnapshot = FinancialTripSnapshotCollection(rows: snapshotRows)
                    } label: {
                        Label("详细信息", systemImage: "list.bullet.rectangle")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("查看所选日期内的行程快照")
                }
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
            "财务": "財務", "行程费用": "行程費用", "小费": "小費", "其他": "其他",
            "上一段日期": "上一段日期", "下一段日期": "下一段日期", "总收入": "總收入", "净收入": "淨收入",
            "暂无收支": "暫無收支", "所选日期内没有财务记录": "所選日期內沒有財務記錄",
            "收支明细": "收支明細", "条行程": "筆行程", "收入": "收入", "支出": "支出",
            "收款方式": "收款方式", "添加": "新增",
            "天": "日", "本周": "本週", "本月": "本月", "年": "年",
            "添加收款方式名称和二维码，方便向客户展示。": "新增收款方式名稱和 QR Code，方便向客戶展示。",
            "收款方式名称": "收款方式名稱",
            "例如：微信、Venmo": "例如：微信、Venmo",
            "添加收款二维码": "新增收款二維碼",
            "点击二维码可直接查看": "點擊二維碼即可檢視",
            "删除收款方式": "刪除收款方式",
            "收款二维码": "收款二維碼",
            "完成": "完成",
            "查看收款二维码": "檢視收款二維碼",
            "选择图片": "選擇圖片",
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
                    .frame(minWidth: 0)
                    .layoutPriority(1)
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
                    ToolbarItem(placement: .topBarLeading) {
                        if let data = method.qrImageData, let image = UIImage(data: data) {
                            ShareLink(item: Image(uiImage: image),
                                      preview: SharePreview(method.name.isEmpty ? AppLocalization.text("收款二维码") : method.name,
                                                            image: Image(uiImage: image))) {
                                Label(AppLocalization.text("分享二维码"), systemImage: "square.and.arrow.up")
                            }
                        }
                    }
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

// Value copies keep this read-only presentation stable while the directory refreshes.
struct FinancialTripSnapshotCollection: Identifiable {
    let id = UUID()
    let rows: [FinancialTripSnapshotRow]
}

struct FinancialTripSnapshotRow: Identifiable {
    let id: String
    let date: Date
    let time: Date
    let guest: String
    let amount: String
    let details: [(String, String)]

    var flightResult: VariFlightLookupResult? = nil

    static func details(service: String, start: String, stops: [String], end: String,
                        flight: String, completed: Bool, cancelled: Bool, paid: Bool,
                        contact: String, passengers: String, luggage: String,
                        agency: String, order: String, memo: String) -> [(String, String)] {
        var rows = [("类型", service), ("状态", cancelled ? "已取消" : completed ? "已完成" : "待执行"),
                    ("收款", paid ? "已结清" : "未收款"), ("联系电话", contact),
                    ("人数", passengers), ("行李", luggage), ("起始点", start)]
        rows += stops.enumerated().map { ("停靠点 \($0.offset + 1)", $0.element) }
        rows += [("目的地", end), ("航班", flight), ("旅行社", agency), ("旅行社订单号", order), ("备注", memo)]
        return rows.filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

struct FinancialTripSnapshotSheet: View {
    let snapshot: FinancialTripSnapshotCollection
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if snapshot.rows.isEmpty {
                        ContentUnavailableView("暂无行程", systemImage: "calendar", description: Text("所选日期内没有行程"))
                    }
                    ForEach(snapshot.rows) { row in
                        DisclosureGroup {
                            FinancialSnapshotRecordCard(row: row)
                                .padding(.top, 12)
                        } label: {
                            HStack(spacing: 12) {
                                VStack(spacing: 3) {
                                    Text(row.time.formatted(.dateTime.hour().minute().locale(locale)))
                                        .font(.system(size: 17, weight: .bold)).monospacedDigit()
                                    Text(row.date.formatted(.dateTime.year().month().day().locale(locale)))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                Text(row.guest.isEmpty ? "未填写客户" : row.guest)
                                    .font(.headline).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                                Text(row.amount).font(.headline).foregroundStyle(.primary)
                            }
                            .padding(.vertical, 4)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    }
                }.padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("行程快照")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { dismiss() } } }
        }
    }
}


/// Read-only counterpart of the trip-list record: time tile, service/facts,
/// connected route, saved flight information and status capsules.
private struct FinancialSnapshotRecordCard: View {
    let row: FinancialTripSnapshotRow
    private func value(_ key: String) -> String { row.details.first { $0.0 == key }?.1 ?? "" }
    private var route: [(String, String)] {
        row.details.filter { $0.0 == "起始点" || $0.0.hasPrefix("停靠点") || $0.0 == "目的地" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Label(LocalizedStringKey(value("类型")), systemImage: value("类型").contains("送") ? "airplane.departure" : "airplane.arrival")
                TripAgencyBadge(orderSource: value("旅行社").isEmpty ? "" : "旅行社订单", agencyName: value("旅行社"))
            }
                .font(.subheadline.weight(.medium)).foregroundStyle(Color.accentColor)
            HStack(spacing: 6) {
                fact("\(value("人数")) 位乘客", icon: "person.fill")
                fact("\(value("行李")) 件行李", icon: "suitcase.fill")
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(route.enumerated()), id: \.offset) { index, point in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(spacing: 4) {
                            Image(systemName: index == 0 ? "mappin.and.ellipse" : point.0 == "目的地" ? "flag.checkered" : "mappin.circle.fill")
                                .foregroundStyle(index == 0 ? Color.teal : .orange)
                            if index < route.count - 1 { Rectangle().fill(Color.secondary.opacity(0.18)).frame(width: 2, height: 24) }
                        }.frame(width: 18)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(point.0).font(.caption).foregroundStyle(.secondary)
                            Text(point.1).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                        }
                    }
                }
            }
            if !value("航班").isEmpty || row.flightResult != nil {
                VStack(alignment: .leading, spacing: 8) {
                    FlightInformationPanel(
                        flightNumber: value("航班"), flightDate: row.date,
                        result: row.flightResult ?? VariFlightLookupResult(
                            airlineName: nil, departureAirport: nil, arrivalAirport: nil,
                            departureTerminal: nil, arrivalTerminal: nil, departureTime: nil,
                            estimatedArrivalTime: nil, baggageCarousel: nil),
                        isLoading: false, error: nil, departureFallback: "", arrivalFallback: "",
                        departureTimeZone: "", arrivalTimeZone: ""
                    )
                    if let baggage = row.flightResult?.baggageCarousel, !baggage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        LabeledContent("行李转盘", value: baggage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(Color.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
            }
            HStack(spacing: 8) {
                Text(value("状态")).font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.10), in: Capsule()).foregroundStyle(Color.accentColor)
                Text(value("收款")).font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.green.opacity(0.10), in: Capsule()).foregroundStyle(.green)
            }
            if !value("备注").isEmpty { Text(value("备注")).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func fact(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon).font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
    }
}
