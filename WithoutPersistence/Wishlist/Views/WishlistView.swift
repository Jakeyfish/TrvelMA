/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Displays recent trips, explorer goals, and trip collections.
*/

import SwiftUI
import SwiftData

/// The main wishlist view displaying trip-related content.
///
/// This view serves as the primary interface for browsing trips in
/// a vertically scrolling layout.
struct WishlistView: View {

    /// The data source containing trip collections.
    @Environment(DataSource.self) private var dataSource
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.modelContext) private var modelContext

    /// Indicates whether the sheet to add a trip is being presented.
    @State private var isPresentingAddTrip = false
    @State private var isPresentingLanguageSettings = false
    @State private var isPresentingNavigationSettings = false
    @State private var isPresentingFlightAwareSettings = false
    @State private var isPresentingPrivacyPolicy = false
    @State private var isPerson = false
    @State private var accountDeletionAlert: AccountDeletionAlert?

    /// The namespace used for coordinating a navigation transition.
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    TripListDashboardView()
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
            }
            .contentMargins(.bottom, 30, for: .scrollContent)
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 7) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 29, height: 29)
                            .background(Color.accentColor.opacity(0.12), in: Circle())
                            .overlay(Circle().stroke(Color.accentColor.opacity(0.12), lineWidth: 1))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.currentSalutation.isEmpty ? "欢迎回来" : auth.currentSalutation)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                            HStack(spacing: 4) {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 9, weight: .medium))
                                Text(auth.currentEmail)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .foregroundStyle(.secondary)
                            .frame(width: 122, alignment: .leading)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityElement(children: .combine)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        Button {
                            isPerson = true
                        } label: {
                            ToolbarCircleIcon(systemName: "person.fill")
                        }
                        .matchedTransitionSource(id: "person", in: namespace)

                        Menu {
                            Button {
                                isPresentingLanguageSettings = true
                            } label: {
                                Label("语言设置", systemImage: "globe")
                            }

                            Button {
                                isPresentingNavigationSettings = true
                            } label: {
                                Label("默认导航", systemImage: "arrow.triangle.turn.up.right.diamond")
                            }

                            Button {
                                isPresentingFlightAwareSettings = true
                            } label: {
                                Label("航班查询设置", systemImage: "airplane")
                            }

                            Button {
                                isPresentingPrivacyPolicy = true
                            } label: {
                                Label("隐私政策", systemImage: "hand.raised.fill")
                            }

                            Button(role: .destructive) {
                                accountDeletionAlert = .confirmation
                            } label: {
                                Label("删除账户", systemImage: "person.crop.circle.badge.xmark")
                            }

                            Divider()

                            Button(role: .destructive) {
                                auth.logout()
                            } label: {
                                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            ToolbarCircleIcon(systemName: "gearshape")
                        }
                        .matchedTransitionSource(id: "setup", in: namespace)
                        .menuStyle(.borderlessButton)

                        Button {
                            isPresentingAddTrip = true
                        } label: {
                            ToolbarCircleIcon(systemName: "plus")
                        }
                        .matchedTransitionSource(id: "addTrip", in: namespace)
                    }
                    .buttonStyle(.plain)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .sheet(isPresented: $isPresentingAddTrip) {
//                AddTripFormView(isPresented: $isPresentingAddTrip)
//                AddTripView(isPresented: $isPresentingAddTrip)
                   AddTripFormView(isPresented: $isPresentingAddTrip)
                    .navigationTransition(
                        .zoom(sourceID: "addTrip", in: namespace))
            }
            .sheet(isPresented: $isPresentingLanguageSettings) {
                LanguageSettingsView()
            }
            .sheet(isPresented: $isPresentingNavigationSettings) {
                DefaultNavigationSettingsView()
            }
            .sheet(isPresented: $isPresentingFlightAwareSettings) {
                FlightAwareSettingsView()
            }
            .sheet(isPresented: $isPresentingPrivacyPolicy) {
                PrivacyPolicyView()
            }
            .alert(item: $accountDeletionAlert) { alert in
                switch alert {
                case .confirmation:
                    Alert(
                        title: Text("确定删除账户？"),
                        message: Text("此操作将删除此设备上的全部账户及相关本地资料，并清空登录状态和本地缓存。删除后无法恢复。当前版本未接入云端存储，因此没有云端数据可删除。"),
                        primaryButton: .destructive(Text("删除"), action: deleteAccount),
                        secondaryButton: .cancel(Text("取消"))
                    )
                case .failure(let message):
                    Alert(
                        title: Text("删除失败"),
                        message: Text(message),
                        dismissButton: .default(Text("关闭"))
                    )
                }
            }
            
            .toolbarTitleDisplayMode(.inline)
            .toolbarRole(.editor)
            .font(.system(size: 12))
            .task(id: auth.currentEmail) {
                auth.refreshCurrentSalutation(context: modelContext)
            }
            
        }
    }

    private func deleteAccount() {
        do {
            try auth.deleteAllLocalData(context: modelContext)
            dataSource.clearAllUserData()
        } catch {
            accountDeletionAlert = .failure(error.localizedDescription)
        }
    }
}

private enum AccountDeletionAlert: Identifiable {
    case confirmation
    case failure(String)

    var id: String {
        switch self {
        case .confirmation: "confirmation"
        case .failure: "failure"
        }
    }
}

private struct ToolbarCircleIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Color.accentColor, in: Circle())
            .contentShape(Circle())
    }
}

private struct TripListDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var bookings: [TripBookingRecord]
    @State private var searchText = ""
    @State private var selectedFilter: TripListFilter = .pending
    @AppStorage("tripList.selectedDateTimestamp") private var selectedDateTimestamp = Date.now.timeIntervalSince1970
    @State private var dateMode: TripDateMode = .sevenDays

    private var selectedDate: Date { Date(timeIntervalSince1970: selectedDateTimestamp) }

    private var visibleBookings: [TripBookingRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return bookings.filter { booking in
            let matchesStatus: Bool
            switch selectedFilter {
            case .pending: matchesStatus = !booking.isCompleted
            case .unpaid: matchesStatus = !booking.isPaid
            case .all: matchesStatus = true
            case .history: matchesStatus = calendar.startOfDay(for: booking.appointmentDate) < today
            }
            guard matchesStatus else { return false }
            if selectedFilter != .history && !calendar.isDate(booking.appointmentDate, inSameDayAs: selectedDate) { return false }
            guard !query.isEmpty else { return true }
            return [booking.customerName, booking.customerContact, booking.serviceType, booking.locationStart,
                    booking.locationEnd, booking.flightInfo, booking.orderSource, booking.memo]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted {
            if !calendar.isDate($0.appointmentDate, inSameDayAs: $1.appointmentDate) { return $0.appointmentDate < $1.appointmentDate }
            return $0.appointmentTime < $1.appointmentTime
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("查找行程").font(.title3.weight(.bold)).foregroundStyle(.primary)
                    Text("按客户、地点或航班搜索").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 5) {
                ForEach(TripDateMode.allCases) { mode in
                    Button { dateMode = mode } label: {
                        Text(LocalizedStringKey(mode.title))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(dateMode == mode ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(dateMode == mode ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

            if dateMode == .sevenDays {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(0..<7, id: \.self) { offset in
                            if let day = Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: .now)) {
                                dateButton(for: day)
                            }
                        }
                    }
                }.scrollIndicators(.hidden)
            } else {
                DatePicker("选择日期", selection: Binding(
                    get: { selectedDate },
                    set: { selectedDateTimestamp = $0.timeIntervalSince1970 }
                ), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(.accentColor)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索客户、地点、航班", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.secondary.opacity(0.16), lineWidth: 1))

            HStack(spacing: 7) {
                ForEach(TripListFilter.allCases) { filter in
                    Button { selectedFilter = filter } label: {
                        Text(LocalizedStringKey(filter.title))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selectedFilter == filter ? Color.accentColor : Color.secondary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(selectedFilter == filter ? Color.accentColor.opacity(0.11) : Color(.secondarySystemGroupedBackground), in: Capsule())
                            .overlay(Capsule().stroke(selectedFilter == filter ? Color.accentColor.opacity(0.48) : Color.secondary.opacity(0.14), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            HStack {
                Text(LocalizedStringKey(selectedFilter == .all ? "全部行程" : selectedFilter.title))
                    .font(.headline.weight(.bold))
                Spacer()
                Text("\(visibleBookings.count)").font(.caption).foregroundStyle(.secondary)
            }

            if visibleBookings.isEmpty {
                ContentUnavailableView(
                    LocalizedStringKey(searchText.isEmpty ? "暂无行程" : "没有找到行程"),
                    systemImage: searchText.isEmpty ? "calendar" : "magnifyingglass",
                    description: Text(LocalizedStringKey(searchText.isEmpty ? "新增行程后会显示在这里。" : "请更换搜索内容或筛选条件。"))
                ).padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(visibleBookings, id: \.id) { booking in
                        NavigationLink {
                            TripBrowseView(booking: booking)
                        } label: {
                            TripManagementCard(booking: booking)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dateButton(for date: Date) -> some View {
        let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let title = Calendar.current.isDateInToday(date) ? "今天" : (Calendar.current.isDateInTomorrow(date) ? "明天" : date.formatted(.dateTime.weekday(.wide)))
        let count = bookings.filter { Calendar.current.isDate($0.appointmentDate, inSameDayAs: date) }.count
        return Button { selectedDateTimestamp = Calendar.current.startOfDay(for: date).timeIntervalSince1970 } label: {
            VStack(spacing: 3) {
                Text(LocalizedStringKey(title)).font(.system(size: 11, weight: .medium))
                Text(date.formatted(.dateTime.month(.twoDigits).day(.twoDigits))).font(.system(size: 15, weight: .bold, design: .rounded))
                HStack(spacing: 2) {
                    Text("\(count)")
                    Text("单")
                }
                .font(.system(size: 10))
                .opacity(0.8)
            }
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .frame(width: 72, height: 70)
            .background(selected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.15), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

private enum TripListFilter: String, CaseIterable, Identifiable {
    case pending, unpaid, all, history
    var id: Self { self }
    var title: String {
        switch self {
        case .pending: "待处理"
        case .unpaid: "未收款"
        case .all: "全部"
        case .history: "历史"
        }
    }
}

private enum TripDateMode: String, CaseIterable, Identifiable {
    case sevenDays, month
    var id: Self { self }
    var title: String { self == .sevenDays ? "7 天" : "月历" }
}

private struct TripManagementCard: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var booking: TripBookingRecord

    private var appointmentDateTime: Date {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: booking.appointmentDate)
        let time = Calendar.current.dateComponents([.hour, .minute], from: booking.appointmentTime)
        return Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute)) ?? booking.appointmentDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 11) {
                VStack(spacing: 4) {
                    Text(appointmentDateTime, format: .dateTime.hour().minute())
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(booking.appointmentDate, format: .dateTime.month(.abbreviated).day())
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                .frame(width: 72, height: 58)
                .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(booking.customerName).font(.headline.weight(.bold)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(booking.price, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .font(.headline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
                    }
                    Label(LocalizedStringKey(booking.serviceType), systemImage: serviceIcon)
                        .font(.subheadline.weight(.medium)).foregroundStyle(Color.accentColor)
                    HStack(spacing: 6) {
                        infoPill(Text("\(booking.customerCount)位乘客"), icon: "person.fill")
                        infoPill(Text("\(booking.customerStuff)件行李"), icon: "suitcase.fill")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 7) {
                routeRow(title: "上车点", value: booking.locationStart, color: .teal, isLast: false)
                routeRow(title: "目的地", value: booking.locationEnd, color: .orange, isLast: true)
            }

            if !booking.flightInfo.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "airplane").foregroundStyle(Color.accentColor)
                    Text(booking.flightInfo).font(.subheadline.weight(.semibold))
                    Text(booking.flightDate, format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(LocalizedStringKey("航班")).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
                .padding(10)
                .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 9) {
                statusBadge(title: booking.isCompleted ? "已完成" : "待执行", isOn: booking.isCompleted, tint: .accentColor)
                statusBadge(title: booking.isPaid ? "已结清" : "未结款", isOn: booking.isPaid, tint: .green)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(13)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private var serviceIcon: String {
        switch booking.serviceType {
        case "接机": "airplane.arrival"
        case "送机": "airplane.departure"
        case "接送", "包车": "car.fill"
        default: "figure.wave"
        }
    }

    private func infoPill(_ title: Text, icon: String) -> some View {
        Label {
            title
        } icon: {
            Image(systemName: icon)
        }
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(Color(.systemGroupedBackground), in: Capsule())
            .lineLimit(1).minimumScaleFactor(0.75)
    }

    private func routeRow(title: String, value: String, color: Color, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle().fill(color).frame(width: 9, height: 9)
                if !isLast { Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 2, height: 23) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
                Text(value.isEmpty ? String(localized: "未填写") : value).font(.subheadline.weight(.medium)).foregroundStyle(value.isEmpty ? Color.secondary : Color.primary).lineLimit(2)
            }
        }
    }

    private func statusBadge(title: String, isOn: Bool, tint: Color) -> some View {
            Text(LocalizedStringKey(title)).font(.caption.weight(.semibold))
                .foregroundStyle(isOn ? tint : Color.secondary)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(isOn ? tint.opacity(0.13) : Color(.systemGroupedBackground), in: Capsule())
    }
}

private struct TripBrowseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Bindable var booking: TripBookingRecord

    private var appointmentDateTime: Date {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: booking.appointmentDate)
        let time = Calendar.current.dateComponents([.hour, .minute], from: booking.appointmentTime)
        return Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute)) ?? booking.appointmentDate
    }

    var body: some View {
        List {
            Section("订单信息") {
                LabeledContent("客户", value: valueOrFallback(booking.customerName))
                LabeledContent("联系方式", value: valueOrFallback(booking.customerContact))
                LabeledContent("行程类型", value: valueOrFallback(booking.serviceType))
                LabeledContent("订单来源", value: valueOrFallback(booking.orderSource))
                LabeledContent("行程费用", value: booking.price, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
            }

            Section("时间与乘客") {
                LabeledContent("接载时间", value: appointmentDateTime.formatted(date: .long, time: .shortened))
                LabeledContent("乘客人数", value: "\(booking.customerCount) 位")
                LabeledContent("行李数量", value: "\(booking.customerStuff) 件")
            }

            Section("行程路线") {
                navigationAddressRow(title: "起始点", address: booking.locationStart)
                navigationAddressRow(title: "目的地", address: booking.locationEnd)
            }

            if !booking.flightInfo.isEmpty {
                Section("航班信息") {
                    LabeledContent("航班号", value: booking.flightInfo)
                    LabeledContent("航班日期", value: booking.flightDate.formatted(date: .long, time: .omitted))
                    if let value = booking.flightDepartureTime, !value.isEmpty {
                        LabeledContent("起飞时间", value: value)
                    }
                    if let value = booking.flightEstimatedArrivalTime, !value.isEmpty {
                        LabeledContent("预计到达时间", value: value)
                    }
                    if let value = booking.flightArrivalTerminal, !value.isEmpty {
                        LabeledContent("到达航站楼", value: value)
                    }
                    if let value = booking.flightBaggageCarousel, !value.isEmpty {
                        LabeledContent("行李转盘", value: value)
                    }
                }
            }

            Section("状态") {
                LabeledContent("行程状态", value: String(localized: booking.isCompleted ? "已完成" : "待执行"))
                Toggle("行程已完成", isOn: $booking.isCompleted)
                    .onChange(of: booking.isCompleted) { _, _ in saveChanges() }
                Picker("结算状态", selection: $booking.isPaid) {
                    Text("未结款").tag(false)
                    Text("已结清").tag(true)
                }
                .pickerStyle(.segmented)
                    .onChange(of: booking.isPaid) { _, _ in saveChanges() }
            }

            if !booking.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("备注") {
                    Text(booking.memo)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("行程详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func navigationAddressRow(title: String, address: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(LocalizedStringKey(title))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("未填写")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    guard let url = NavigationProvider.selected.directionsURL(for: address) else { return }
                    openURL(url)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(address)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
    }

    private func valueOrFallback(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "未填写") : value
    }

    private func saveChanges() {
        try? modelContext.save()
    }
}

private extension TripCollection {
    var cardSize: TripCard.Size {
        (summary?.isEmpty == false) ? .expanded : .compact
    }
}



// MARK: - ========================================================
// MARK: - 以下为完全私有化隔离的 3D 风琴折叠卡片组件（纯原生现代API完整版）
// MARK: - ========================================================

struct WishlistFoldingFormModel {
    var passengerName: String = ""
    var idCard: String = ""
    var phoneNumber: String = ""
    var mealPreference: String = "标准餐"
}

struct MultiFoldingFormView: View {
    @State private var isExpanded = false
    @State private var formData = WishlistFoldingFormModel()
    
    var body: some View {
        VStack(spacing: 0) {
            HeaderPanel(isExpanded: isExpanded) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75, blendDuration: 0)) {
                    isExpanded.toggle()
                }
            }
            .zIndex(10)
            
            AccordionContainer(isExpanded: isExpanded, formData: $formData)
        }
    }
}

struct AccordionContainer: View {
    let isExpanded: Bool
    @Binding var formData: WishlistFoldingFormModel
    private let sliceHeight: CGFloat = 90
    
    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                WishlistFormSliceOne(formData: $formData, height: sliceHeight)
                    .transition(.asymmetric(
                        insertion: .modifier(active: WishlistVStackFoldModifier(sliceIndex: 1, progress: 1), identity: WishlistVStackFoldModifier(sliceIndex: 1, progress: 0)),
                        removal: .modifier(active: WishlistVStackFoldModifier(sliceIndex: 1, progress: 1), identity: WishlistVStackFoldModifier(sliceIndex: 1, progress: 0))
                    ))
                    .zIndex(9)
                
                WishlistFormSliceTwo(formData: $formData, height: sliceHeight)
                    .transition(.asymmetric(
                        insertion: .modifier(active: WishlistVStackFoldModifier(sliceIndex: 2, progress: 1), identity: WishlistVStackFoldModifier(sliceIndex: 2, progress: 0)),
                        removal: .modifier(active: WishlistVStackFoldModifier(sliceIndex: 2, progress: 1), identity: WishlistVStackFoldModifier(sliceIndex: 2, progress: 0))
                    ))
                    .zIndex(8)
                
                WishlistFormSliceThree(formData: $formData, height: sliceHeight)
                    .transition(.asymmetric(
                        insertion: .modifier(active: WishlistVStackFoldModifier(sliceIndex: 3, progress: 1), identity: WishlistVStackFoldModifier(sliceIndex: 3, progress: 0)),
                        removal: .modifier(active: WishlistVStackFoldModifier(sliceIndex: 3, progress: 1), identity: WishlistVStackFoldModifier(sliceIndex: 3, progress: 0))
                    ))
                    .zIndex(7)
            }
        }
        .clipped()
    }
}

struct WishlistVStackFoldModifier: ViewModifier {
    let sliceIndex: Int
    let progress: Double
    
    func body(content: Content) -> some View {
        let isOdd = sliceIndex % 2 != 0
        let angle = isOdd ? (progress * -90.0) : (progress * 90.0)
        let anchor: UnitPoint = isOdd ? .top : .bottom
        
        return content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 1.0, y: 0.0, z: 0.0),
                anchor: anchor,
                perspective: 0.4
            )
            .opacity(1.0 - progress)
            .scaleEffect(y: 1.0 - progress, anchor: anchor)
    }
}

struct HeaderPanel: View {
    let isExpanded: Bool
    let action: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("行程列表")
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text(LocalizedStringKey(isExpanded ? "点击收起详细表单" : "展开填写多项服务登记"))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            Spacer()
//            HStack(spacing: 12) {
//                Image(systemName: "person.circle.fill").font(.title3)
//                Image(systemName: "gearshape.circle.fill").font(.title3)
//                Image(systemName: "plus.circle.fill").font(.title3)
//            }
//            .foregroundColor(.white.opacity(0.9))
        }
        .padding()
        .frame(height: 75)
        .background(
            LinearGradient(gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                bottomLeadingRadius: isExpanded ? 0 : 16,
                bottomTrailingRadius: isExpanded ? 0 : 16,
                topTrailingRadius: 16
            )
        )
        .onTapGesture(perform: action)
    }
}

struct WishlistFormSliceOne: View {
    @Binding var formData: WishlistFoldingFormModel
    let height: CGFloat
    
    var body: some View {
        VStack(spacing: 8) {
            TextField("乘客姓名", text: $formData.passengerName)
                .nativeIMEInput()
                .textFieldStyle(.roundedBorder)
        }
        .padding()
        .frame(height: height)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

struct WishlistFormSliceTwo: View {
    @Binding var formData: WishlistFoldingFormModel
    let height: CGFloat
    
    var body: some View {
        VStack(spacing: 8) {
            TextField("手机号码", text: $formData.phoneNumber)
                .keyboardType(.phonePad)
                .textFieldStyle(.roundedBorder)
        }
        .padding()
        .frame(height: height)
        .background(Color(.secondarySystemGroupedBackground))
    }
}

struct WishlistFormSliceThree: View {
    @Binding var formData: WishlistFoldingFormModel
    let height: CGFloat
    
    var body: some View {
        VStack(spacing: 12) {
            Picker("机上餐饮", selection: $formData.mealPreference) {
                Text("标准餐").tag("standard")
                Text("素食").tag("veggie")
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .frame(height: height)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 0
            )
        )
    }
}


#Preview {
    @Previewable @State var dataSource = DataSource()
    @Previewable @State var auth = AuthViewModel()
    WishlistView()
        .environment(dataSource)
        .environment(auth)
        .modelContainer(for: [
            Custumer.self,
            Address.self,
            Connect.self,
            LoginInfo.self,
            ProfileInfo.self,
            LocalAccount.self,
            TripBookingRecord.self
        ], inMemory: true)
}
