/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Displays recent trips, explorer goals, and trip collections.
*/

import SwiftUI
import SwiftData
import UserNotifications
import CoreLocation

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
    @State private var isPresentingBaseCurrencySettings = false
    @State private var isPresentingFlightSettings = false
    @State private var isPresentingCloudSyncSettings = false
    @State private var isPresentingExpenseItems = false
    @State private var isPresentingPrivacyPolicy = false
    @State private var isPresentingCooperativeAgencies = false
    @State private var isPerson = false
    @State private var accountDeletionAlert: AccountDeletionAlert?

    /// The namespace used for coordinating a navigation transition.
    @Namespace private var namespace

    private var accountEmailWidth: CGFloat {
        // The email label includes the envelope icon and its spacing.
        min(max(CGFloat(auth.currentEmail.count) * 6.2 + 16, 122), 205)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TripListDashboardView(showsDateControls: false)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
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
                            .frame(width: accountEmailWidth, alignment: .leading)
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityElement(children: .combine)
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        Menu {
                            Button {
                                isPresentingCooperativeAgencies = true
                            } label: {
                                Label("合作旅行社", systemImage: "building.2.fill")
                            }
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
                                isPresentingBaseCurrencySettings = true
                            } label: {
                                Label("本位币设置", systemImage: "dollarsign.circle")
                            }

                            Button {
                                isPresentingFlightSettings = true
                            } label: {
                                Label("航班查询设置", systemImage: "airplane")
                            }

                            Button {
                                isPresentingCloudSyncSettings = true
                            } label: {
                                Label("数据同步设置", systemImage: "arrow.triangle.2.circlepath.icloud")
                            }

                            Button {
                                isPresentingExpenseItems = true
                            } label: {
                                Label("费用项目管理", systemImage: "list.bullet.rectangle")
                            }

                            Button {
                                isPresentingPrivacyPolicy = true
                            } label: {
                                Label("隐私政策", systemImage: "hand.raised.fill")
                            }

                            if auth.isCloudAccount {
                                Button(role: .destructive) {
                                    accountDeletionAlert = .cloudLocalDataConfirmation
                                } label: {
                                    Label("清除此账号的本机资料", systemImage: "externaldrive.badge.xmark")
                                }
                                .disabled(auth.isCloudSyncInProgress)
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
            .sheet(isPresented: $isPresentingFlightSettings) {
                VariFlightSettingsView()
            }
            .sheet(isPresented: $isPresentingCloudSyncSettings) {
                CloudSyncPreferenceView()
            }
            .sheet(isPresented: $isPresentingBaseCurrencySettings) {
                BaseCurrencySettingsView()
            }
            .sheet(isPresented: $isPresentingExpenseItems) {
                ExpenseItemManagementView()
            }
            .sheet(isPresented: $isPresentingPrivacyPolicy) {
                PrivacyPolicyView()
            }
            .sheet(isPresented: $isPresentingCooperativeAgencies) {
                TravelAgencyListView()
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
                case .cloudLocalDataConfirmation:
                    Alert(
                        title: Text("清除本机资料？"),
                        message: Text("只会删除当前登录账号保存在此设备上的行程管家资料和缓存。云端数据与其他账号不受影响。清除后无法从本机恢复；云端仍有资料时，可以再次同步下载。"),
                        primaryButton: .destructive(Text("清除本机资料"), action: clearCloudAccountLocalData),
                        secondaryButton: .cancel(Text("取消"))
                    )
                case .failure(let message):
                    Alert(
                        title: Text("删除失败"),
                        message: Text(message),
                        dismissButton: .default(Text("关闭"))
                    )
                case .cloudLocalDataFailure(let message):
                    Alert(
                        title: Text("清除失败"),
                        message: Text(message),
                        dismissButton: .default(Text("关闭"))
                    )
                case .cloudLocalDataSuccess:
                    Alert(
                        title: Text("本机资料已清除"),
                        message: Text("当前账号保存在此设备上的资料和缓存已清除。云端数据与其他账号没有更改。"),
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

    private func clearCloudAccountLocalData() {
        do {
            try auth.clearCurrentCloudAccountLocalData(context: modelContext)
            accountDeletionAlert = .cloudLocalDataSuccess
        } catch {
            accountDeletionAlert = .cloudLocalDataFailure(error.localizedDescription)
        }
    }
}

private enum AccountDeletionAlert: Identifiable {
    case confirmation
    case failure(String)
    case cloudLocalDataConfirmation
    case cloudLocalDataFailure(String)
    case cloudLocalDataSuccess

    var id: String {
        switch self {
        case .confirmation: "confirmation"
        case .failure: "failure"
        case .cloudLocalDataConfirmation: "cloud-local-data-confirmation"
        case .cloudLocalDataFailure: "cloud-local-data-failure"
        case .cloudLocalDataSuccess: "cloud-local-data-success"
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

struct TripsPageView: View {
    @State private var isPresentingAddTrip = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    Text("行程")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    Button {
                        isPresentingAddTrip = true
                    } label: {
                        ToolbarCircleIcon(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新增行程")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)

                TripListDashboardView()
                    .padding(.horizontal, 16)
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $isPresentingAddTrip) {
                AddTripFormView(isPresented: $isPresentingAddTrip)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .font(.system(size: 14))
    }
}

struct TripListDashboardView: View {
    var showsDateControls = true
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @Query private var bookings: [TripBookingRecord]
    @State private var searchText = ""
    @State private var selectedFilter: TripListFilter = .all
    @State private var selectedDateFilter: Date?
    @AppStorage("tripList.selectedDateTimestamp") private var selectedDateTimestamp = Date.now.timeIntervalSince1970
    @State private var dateMode: TripDateMode = .sevenDays
    @State private var isShowingAllDates = true

    init(showsDateControls: Bool = true) {
        self.showsDateControls = showsDateControls
        let scope = DataOwnership.activeScope
        _bookings = Query(filter: #Predicate { $0.ownerScope == scope })
    }

    private var selectedDate: Date { Date(timeIntervalSince1970: selectedDateTimestamp) }

    private var datesWithBookings: [Date] {
        let calendar = Calendar.current
        if showsDateControls {
            return Array(Set(bookings.map { calendar.startOfDay(for: $0.appointmentDate) })).sorted()
        }

        let today = calendar.startOfDay(for: .now)
        return Array(Set(bookings.filter {
            !$0.isCompleted
                && !$0.isCancelled
                && calendar.startOfDay(for: $0.appointmentDate) >= today
        }.map { calendar.startOfDay(for: $0.appointmentDate) })).sorted()
    }

    private var visibleBookings: [TripBookingRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return bookings.filter { booking in
            let matchesStatus: Bool
            if !showsDateControls {
                matchesStatus = !booking.isCompleted && !booking.isCancelled && calendar.startOfDay(for: booking.appointmentDate) >= today
            } else {
                switch selectedFilter {
                case .pending: matchesStatus = !booking.isCompleted && !booking.isCancelled
                case .unpaid: matchesStatus = !booking.isPaid
                case .all: matchesStatus = true
                case .history: matchesStatus = calendar.startOfDay(for: booking.appointmentDate) < today
                }
            }
            guard matchesStatus else { return false }
            if showsDateControls,
               let selectedDateFilter,
               !calendar.isDate(booking.appointmentDate, inSameDayAs: selectedDateFilter) { return false }
            if !showsDateControls,
               !isShowingAllDates,
               !calendar.isDate(booking.appointmentDate, inSameDayAs: selectedDate) { return false }
            guard !query.isEmpty else { return true }
            return [booking.customerName, booking.customerContact, booking.serviceType, booking.locationStart,
                    booking.locationStops.joined(separator: " "), booking.locationEnd, booking.flightInfo, booking.orderSource, booking.memo]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted {
            if !calendar.isDate($0.appointmentDate, inSameDayAs: $1.appointmentDate) { return $0.appointmentDate < $1.appointmentDate }
            return $0.appointmentTime < $1.appointmentTime
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsDateControls {
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

            }

            // 首页不显示“7天 / 月历”切换和月历，但仍保留下方的 7 天日期筛选卡片。
            if !showsDateControls || dateMode == .sevenDays {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        if !showsDateControls {
                            allPendingDatesButton
                        }
                        ForEach(datesWithBookings, id: \.self) { day in
                            dateButton(for: day)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            } else if showsDateControls && dateMode == .month {
                DatePicker("选择日期", selection: Binding(
                    get: { selectedDateFilter ?? selectedDate },
                    set: {
                        selectedDateTimestamp = $0.timeIntervalSince1970
                        selectedDateFilter = Calendar.current.startOfDay(for: $0)
                    }
                ), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(.accentColor)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                SystemIMETextField(
                    text: $searchText,
                    placeholder: String(localized: "搜索客户、地点、航班", locale: locale),
                    capitalization: .none
                )
                .frame(height: 20)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.secondary.opacity(0.16), lineWidth: 1))

            if showsDateControls {
            HStack(spacing: 7) {
                ForEach(TripListFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                        selectedDateFilter = nil
                    } label: {
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
            }

            HStack {
                Text(LocalizedStringKey(showsDateControls ? (selectedFilter == .all ? "全部行程" : selectedFilter.title) : "待执行行程"))
                    .font(.headline.weight(.bold))
                Spacer()
                Text("\(visibleBookings.count)").font(.caption).foregroundStyle(.secondary)
            }

            ScrollView(.vertical) {
                if visibleBookings.isEmpty {
                    ContentUnavailableView(
                        LocalizedStringKey(searchText.isEmpty ? "暂无行程" : "没有找到行程"),
                        systemImage: searchText.isEmpty ? "calendar" : "magnifyingglass",
                        description: Text(LocalizedStringKey(searchText.isEmpty ? "新增行程后会显示在这里。" : "请更换搜索内容或筛选条件。"))
                    )
                    .padding(.vertical, 12)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(visibleBookings, id: \.id) { booking in
                            TripManagementCard(booking: booking)
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
        }
        .onAppear {
            if !showsDateControls,
               !isShowingAllDates,
               !datesWithBookings.contains(where: { Calendar.current.isDate($0, inSameDayAs: selectedDate) }),
               let firstAvailableDate = datesWithBookings.first {
                selectedDateTimestamp = firstAvailableDate.timeIntervalSince1970
            }
        }
        .onChange(of: datesWithBookings) { _, newDates in
            guard !showsDateControls,
                  !isShowingAllDates,
                  !newDates.isEmpty,
                  !newDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: selectedDate) }),
                  let firstAvailableDate = newDates.first else { return }
            selectedDateTimestamp = firstAvailableDate.timeIntervalSince1970
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var allPendingDatesButton: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let count = bookings.filter {
            !$0.isCompleted
                && !$0.isCancelled
                && Calendar.current.startOfDay(for: $0.appointmentDate) >= today
        }.count
        return Button {
            isShowingAllDates = true
        } label: {
            VStack(spacing: 3) {
                Text("全部").font(.system(size: 11, weight: .medium))
                Text("行程").font(.system(size: 15, weight: .bold, design: .rounded))
                Text(orderCountLabel(count))
                .font(.system(size: 10))
                .opacity(0.8)
            }
            .foregroundStyle(isShowingAllDates ? Color.white : Color.primary)
            .frame(width: 68, height: 66)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(isShowingAllDates ? Color.accentColor : Color(.secondarySystemGroupedBackground))
            }
        }
        .buttonStyle(.plain)
    }

    private func dateButton(for date: Date) -> some View {
        let selected = showsDateControls
            ? selectedDateFilter.map { Calendar.current.isDate(date, inSameDayAs: $0) } ?? false
            : !isShowingAllDates && Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let title = Calendar.current.isDateInToday(date)
            ? String(localized: "今天", locale: locale)
            : Calendar.current.isDateInTomorrow(date)
                ? String(localized: "明天", locale: locale)
                : date.formatted(.dateTime.weekday(.wide).locale(locale))
        let count = bookings.filter {
            (showsDateControls || (!$0.isCompleted && !$0.isCancelled)) && Calendar.current.isDate($0.appointmentDate, inSameDayAs: date)
        }.count
        return Button {
            let day = Calendar.current.startOfDay(for: date)
            isShowingAllDates = false
            selectedDateTimestamp = day.timeIntervalSince1970
            if showsDateControls { selectedDateFilter = day }
        } label: {
            VStack(spacing: 3) {
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                Text(date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).locale(locale))).font(.system(size: 15, weight: .bold, design: .rounded))
                Text(orderCountLabel(count))
                .font(.system(size: 10))
                .opacity(0.8)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(width: 68, height: 66)
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(selected
                        ? AnyShapeStyle(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color(.secondarySystemGroupedBackground)))
            }
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(selected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.15), lineWidth: 1))
            .shadow(color: selected ? Color.accentColor.opacity(0.22) : .clear, radius: 7, x: 0, y: 3)
        }.buttonStyle(.plain)
    }

    private func orderCountLabel(_ count: Int) -> String {
        return switch locale.language.languageCode?.identifier {
        case "en": count == 1 ? "1 order" : "\(count) orders"
        case "es": count == 1 ? "1 viaje" : "\(count) viajes"
        case "ja": "\(count) 件"
        case "ko": "\(count)건"
        case "zh" where locale.identifier.contains("Hant") || locale.identifier.contains("TW") || locale.identifier.contains("HK"):
            "\(count) 單"
        default: "\(count) 单"
        }
    }
}

private enum TripListFilter: String, CaseIterable, Identifiable {
    case all, pending, unpaid, history
    var id: Self { self }
    var title: String {
        switch self {
        case .pending: "待执行"
        case .unpaid: "未收款"
        case .all: "全部"
        case .history: "历史"
        }
    }
}

private enum TripDateMode: String, CaseIterable, Identifiable {
    case sevenDays, month
    var id: Self { self }
    var title: String { self == .sevenDays ? "周" : "月历" }
}

/// A top-down airplane silhouette whose nose always points to the right.
private struct RightFacingAirplane: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + w * x, y: rect.minY + h * y)
        }

        var path = Path()
        path.move(to: point(1.00, 0.50)) // nose
        path.addLine(to: point(0.58, 0.37))
        path.addLine(to: point(0.48, 0.00))
        path.addLine(to: point(0.37, 0.00))
        path.addLine(to: point(0.40, 0.42))
        path.addLine(to: point(0.12, 0.34))
        path.addLine(to: point(0.04, 0.18))
        path.addLine(to: point(0.00, 0.20))
        path.addLine(to: point(0.08, 0.50))
        path.addLine(to: point(0.00, 0.80))
        path.addLine(to: point(0.04, 0.82))
        path.addLine(to: point(0.12, 0.66))
        path.addLine(to: point(0.40, 0.58))
        path.addLine(to: point(0.37, 1.00))
        path.addLine(to: point(0.48, 1.00))
        path.addLine(to: point(0.58, 0.63))
        path.closeSubpath()
        return path
    }
}

struct FlightInformationPanel: View {
    @Environment(\.locale) private var locale
    let flightNumber: String
    let flightDate: Date
    let result: VariFlightLookupResult?
    let isLoading: Bool
    let error: String?
    let departureFallback: String
    let arrivalFallback: String
    let departureTimeZone: String
    let arrivalTimeZone: String

    var body: some View {
        Group {
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在查询航班信息…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let result {
                flightContent(result)
            }
        }
    }

    private func flightContent(_ result: VariFlightLookupResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                airlineLogo
                VStack(alignment: .leading, spacing: 2) {
                    Text(flightNumber).font(.headline.weight(.bold))
                    if let name = result.airlineName, !name.isEmpty {
                        Text(name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            HStack(spacing: 8) {
                timeColumn(
                    result.departureTime ?? departureFallback,
                    label: "起飞时间",
                    timeZone: departureTimeZone,
                    alignment: .leading,
                    timeZoneOnLeading: false
                )
                directionIndicator
                timeColumn(
                    result.estimatedArrivalTime ?? arrivalFallback,
                    label: "预计到达时间",
                    timeZone: arrivalTimeZone,
                    alignment: .trailing,
                    timeZoneOnLeading: true
                )
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("起飞机场").font(.caption2).foregroundStyle(.secondary)
                    Text(result.departureAirport ?? "—").font(.caption.weight(.semibold)).lineLimit(2)
                    if let terminal = result.departureTerminal, !terminal.isEmpty {
                        Text(String(localized: "出发航站楼 \(terminal)", locale: locale)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("到达机场").font(.caption2).foregroundStyle(.secondary)
                    Text(result.arrivalAirport ?? "—")
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                    if let terminal = result.arrivalTerminal, !terminal.isEmpty {
                        Text(String(localized: "到达航站楼 \(terminal)", locale: locale)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var airlineLogo: some View {
        let code = String(flightNumber.prefix(while: \.isLetter)).uppercased()
        let url = URL(string: "https://www.gstatic.com/flights/airline_logos/70px/\(code).png")
        return Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFit().padding(3) }
                    else { airlineMonogram(code) }
                }
            } else {
                airlineMonogram(code)
            }
        }
        .frame(width: 38, height: 38)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func airlineMonogram(_ code: String) -> some View {
        Text(code.isEmpty ? "✈" : code)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var directionIndicator: some View {
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                Capsule().fill(Color.accentColor.opacity(0.35)).frame(height: 2)
                RightFacingAirplane().fill(Color.accentColor).frame(width: 22, height: 18)
                Capsule().fill(Color.accentColor.opacity(0.35)).frame(height: 2)
            }
            Text("计划").font(.caption2.weight(.semibold)).foregroundStyle(Color.accentColor)
        }
        .frame(width: 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("计划航班方向")
    }

    private func timeColumn(
        _ value: String,
        label: String,
        timeZone: String,
        alignment: HorizontalAlignment,
        timeZoneOnLeading: Bool
    ) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if timeZoneOnLeading {
                    Text(timeZone).foregroundStyle(Color.accentColor).font(.system(size: 9, weight: .medium))
                    timeText(value)
                } else {
                    timeText(value)
                    Text(timeZone).foregroundStyle(Color.accentColor).font(.system(size: 9, weight: .medium))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            Text(LocalizedStringKey(label)).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeText(_ value: String) -> some View {
        Text(timeOnly(value))
            .font(.system(size: 26, weight: .medium, design: .rounded))
            .monospacedDigit()
    }

    private func timeOnly(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "—" }
        let timePart = normalized.split(whereSeparator: { $0 == "T" || $0 == " " }).last.map(String.init) ?? normalized
        let components = timePart.split(separator: ":")
        guard components.count >= 2,
              components[0].allSatisfy(\.isNumber),
              components[1].prefix(2).allSatisfy(\.isNumber) else { return normalized }
        return "\(components[0]):\(components[1].prefix(2))"
    }
}

enum FlightTimeZoneResolver {
    static func label(for airport: String?, date: Date) async -> String? {
        guard let airport, !airport.isEmpty else { return nil }
        let geocoder = CLGeocoder()
        if let placemark = try? await geocoder.geocodeAddressString(airport).first,
           let timeZone = placemark.timeZone {
            return formattedOffset(for: timeZone, date: date)
        }
        guard let fallback = fallbackTimeZone(for: airport) else { return nil }
        return formattedOffset(for: fallback, date: date)
    }

    private static func fallbackTimeZone(for airport: String) -> TimeZone? {
        let value = airport.lowercased()
        let zones: [(String, String)] = [
            ("成都", "Asia/Shanghai"), ("北京", "Asia/Shanghai"), ("上海", "Asia/Shanghai"),
            ("广州", "Asia/Shanghai"), ("深圳", "Asia/Shanghai"), ("香港", "Asia/Hong_Kong"),
            ("台北", "Asia/Taipei"), ("东京", "Asia/Tokyo"), ("大阪", "Asia/Tokyo"),
            ("首尔", "Asia/Seoul"), ("洛杉矶", "America/Los_Angeles"), ("lax", "America/Los_Angeles"),
            ("旧金山", "America/Los_Angeles"), ("sfo", "America/Los_Angeles"),
            ("斯波坎", "America/Los_Angeles"), ("geg", "America/Los_Angeles"),
            ("纽约", "America/New_York"), ("jfk", "America/New_York"),
            ("芝加哥", "America/Chicago"), ("伦敦", "Europe/London"), ("希思罗", "Europe/London")
        ]
        guard let identifier = zones.first(where: { value.contains($0.0.lowercased()) })?.1 else { return nil }
        return TimeZone(identifier: identifier)
    }

    private static func formattedOffset(for timeZone: TimeZone, date: Date) -> String {
        let totalMinutes = timeZone.secondsFromGMT(for: date) / 60
        let sign = totalMinutes >= 0 ? "+" : "−"
        let absoluteMinutes = abs(totalMinutes)
        let hours = absoluteMinutes / 60
        let minutes = absoluteMinutes % 60
        return minutes == 0 ? "GMT\(sign)\(hours)" : "GMT\(sign)\(hours):\(String(format: "%02d", minutes))"
    }
}

private struct TripManagementCard: View {
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var modelContext
    @AppStorage(BaseCurrencyCatalog.countryCodeKey) private var baseCurrencyCountry = BaseCurrencyCatalog.defaultCountryCode
    @Bindable var booking: TripBookingRecord
    @State private var isShowingFinancialSettlement = false
    @State private var isShowingCompletionSettlementPrompt = false
    @State private var isShowingCancellationPrompt = false
    @State private var isFlightExpanded = false
    @State private var isLookingUpFlight = false
    @State private var flightLookupResult: VariFlightLookupResult?
    @State private var flightLookupError: String?
    @State private var departureTimeZoneLabel = ""
    @State private var arrivalTimeZoneLabel = ""

    private var appointmentDateTime: Date {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: booking.appointmentDate)
        let time = Calendar.current.dateComponents([.hour, .minute], from: booking.appointmentTime)
        return Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute)) ?? booking.appointmentDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                TripBrowseView(booking: booking)
            } label: {
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
                                Text(BaseCurrencyCatalog.format(booking.price, countryCode: baseCurrencyCountry))
                                    .font(.headline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
                            }
                            Label(LocalizedStringKey(booking.serviceType), systemImage: serviceIcon)
                                .font(.subheadline.weight(.medium)).foregroundStyle(Color.accentColor)
                            HStack(spacing: 6) {
                                infoPill(Text(passengerCountLabel(booking.customerCount)), icon: "person.fill")
                                infoPill(Text(baggageCountLabel(booking.customerStuff)), icon: "suitcase.fill")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        routeRow(title: "起始点", value: booking.locationStart, color: .teal, isLast: false, icon: "mappin.and.ellipse")
                        ForEach(Array(booking.locationStops.enumerated()), id: \.offset) { index, stop in
                            routeRow(title: String(localized: "停靠点 \(index + 1)", locale: locale), value: stop, color: .orange, isLast: false)
                        }
                        routeRow(title: "目的地", value: booking.locationEnd, color: .orange, isLast: true, icon: "flag.checkered")
                    }

                }
            }
            .buttonStyle(.plain)

            if !booking.flightInfo.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "airplane").foregroundStyle(Color.accentColor)
                        Text(booking.flightInfo).font(.subheadline.weight(.semibold))
                        Text(booking.flightDate, format: .dateTime.month(.abbreviated).day())
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button {
                            let shouldExpand = !isFlightExpanded
                            withAnimation(.easeInOut(duration: 0.2)) { isFlightExpanded = shouldExpand }
                            if shouldExpand && flightLookupResult == nil && !isLookingUpFlight { lookupFlight() }
                        } label: {
                            HStack(spacing: 5) {
                                if isLookingUpFlight { ProgressView().controlSize(.mini) }
                                Text(LocalizedStringKey("航班")).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                                Image(systemName: isFlightExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("查询并显示航班信息")
                    }
                    .padding(10)

                    if isFlightExpanded {
                        flightDetails.padding(.horizontal, 12).padding(.bottom, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }

            HStack(spacing: 9) {
                statusBadge(
                    title: booking.isCancelled ? "已取消" : (booking.isCompleted ? "已完成" : "待执行"),
                    isOn: booking.isCompleted || booking.isCancelled,
                    tint: booking.isCancelled ? .red : .accentColor
                )
                statusBadge(title: booking.isPaid ? "已结清" : "未收款", isOn: booking.isPaid, tint: .green)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }

            if (!booking.isCompleted && !booking.isCancelled) || !booking.isPaid {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if !booking.isCompleted && !booking.isCancelled {
                        Button("已完成") {
                            updateBooking(completed: true)
                            isShowingCompletionSettlementPrompt = true
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .buttonStyle(.plain)

                        Button("取消行程") { isShowingCancellationPrompt = true }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.red)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.10), in: Capsule())
                            .buttonStyle(.plain)
                    }
                    if !booking.isPaid {
                        Button("财务结算") {
                            isShowingFinancialSettlement = true
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12), in: Capsule())
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .confirmationDialog("是否需要取消行程？", isPresented: $isShowingCancellationPrompt, titleVisibility: .visible) {
            Button("是，取消行程", role: .destructive) { setCancelled(true) }
            Button("否", role: .cancel) { }
        }
        .alert("行程已结束", isPresented: $isShowingCompletionSettlementPrompt) {
            Button("否", role: .cancel) { }
            Button("是") {
                isShowingFinancialSettlement = true
            }
        } message: {
            Text("是否财务结算？")
        }
        .sheet(isPresented: $isShowingFinancialSettlement) {
            NavigationStack {
                FinancialSettlementView(booking: booking)
            }
        }
        .padding(13)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    private func passengerCountLabel(_ rawCount: String) -> String {
        let count = Int(rawCount) ?? 0
        return switch locale.language.languageCode?.identifier {
        case "en": count == 1 ? "1 passenger" : "\(count) passengers"
        case "es": count == 1 ? "1 pasajero" : "\(count) pasajeros"
        case "ja": "\(count) 人"
        case "ko": "\(count)명"
        case "zh" where locale.identifier.contains("Hant") || locale.identifier.contains("TW") || locale.identifier.contains("HK"):
            "\(count) 位乘客"
        default: "\(count) 位乘客"
        }
    }

    private func baggageCountLabel(_ rawCount: String) -> String {
        let count = Int(rawCount) ?? 0
        return switch locale.language.languageCode?.identifier {
        case "en": count == 1 ? "1 bag" : "\(count) bags"
        case "es": count == 1 ? "1 maleta" : "\(count) maletas"
        case "ja": "\(count) 個の荷物"
        case "ko": "\(count)개 수하물"
        case "zh" where locale.identifier.contains("Hant") || locale.identifier.contains("TW") || locale.identifier.contains("HK"):
            "\(count) 件行李"
        default: "\(count) 件行李"
        }
    }

    @ViewBuilder
    private var flightDetails: some View {
        FlightInformationPanel(
            flightNumber: booking.flightInfo,
            flightDate: booking.flightDate,
            result: flightLookupResult,
            isLoading: isLookingUpFlight,
            error: flightLookupError,
            departureFallback: booking.flightDepartureTime ?? "",
            arrivalFallback: booking.flightEstimatedArrivalTime ?? "",
            departureTimeZone: departureTimeZoneLabel,
            arrivalTimeZone: arrivalTimeZoneLabel
        )
    }

    private func lookupFlight() {
        isLookingUpFlight = true
        flightLookupError = nil
        Task {
            do {
                let result = try await VariFlightClient().lookup(flightNumber: booking.flightInfo, flightDate: booking.flightDate)
                flightLookupResult = result
                departureTimeZoneLabel = await FlightTimeZoneResolver.label(for: result.departureAirport, date: booking.flightDate) ?? ""
                arrivalTimeZoneLabel = await FlightTimeZoneResolver.label(for: result.arrivalAirport, date: booking.flightDate) ?? ""
            } catch {
                flightLookupError = error.localizedDescription
            }
            isLookingUpFlight = false
        }
    }

    private func updateBooking(completed: Bool) {
        let bookingID = booking.id
        let scope = DataOwnership.activeScope
        let descriptor = FetchDescriptor<TripBookingRecord>(
            predicate: #Predicate { $0.id == bookingID && $0.ownerScope == scope }
        )
        guard let record = try? modelContext.fetch(descriptor).first else { return }
        record.isCompleted = completed
        record.isCancelled = false
        record.updatedAt = .now
        try? modelContext.save()
    }

    private func setCancelled(_ cancelled: Bool) {
        booking.isCancelled = cancelled
        if cancelled { booking.isCompleted = false }
        booking.updatedAt = .now
        try? modelContext.save()
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

    private func routeRow(title: String, value: String, color: Color, isLast: Bool, icon: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 16, height: 16)
                } else {
                    Circle().fill(color).frame(width: 9, height: 9)
                        .frame(width: 16, height: 16)
                }
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

private enum ExpenseItemCatalog {
    private static let storageKey = "financial.expenseItemNames.v1"
    private static let initialNames = ["居间费", "高速通行费"]

    static func load() -> [String] {
        guard UserDefaults.standard.object(forKey: storageKey) != nil else {
            save(initialNames)
            return initialNames
        }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let names = try? JSONDecoder().decode([String].self, from: data) else { return initialNames }
        return names
    }

    static func save(_ names: [String]) {
        var uniqueNames: [String] = []
        for name in names {
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty && !uniqueNames.contains(normalized) {
                uniqueNames.append(normalized)
            }
        }
        guard let data = try? JSONEncoder().encode(uniqueNames) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

private struct ExpenseItemManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expenseNames: [String] = []
    @State private var newExpenseName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(expenseNames.indices, id: \.self) { index in
                        TextField("费用名称", text: $expenseNames[index])
                            .keyboardDoneToolbar()
                            .nativeIMEInput()
                    }
                    .onDelete(perform: deleteExpenseNames)
                } header: {
                    Text("费用名称")
                } footer: {
                    Text("这里维护的名称会用于财务结算中的费用明细选择。")
                }

                Section("添加费用项目") {
                    HStack(spacing: 10) {
                        TextField("输入费用名称", text: $newExpenseName)
                            .keyboardDoneToolbar()
                            .nativeIMEInput()
                        Button("添加", action: addExpenseName)
                            .disabled(newExpenseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("费用项目管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { expenseNames = ExpenseItemCatalog.load() }
            .onChange(of: expenseNames) { _, names in
                ExpenseItemCatalog.save(names)
            }
        }
    }

    private func addExpenseName() {
        let name = newExpenseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              !expenseNames.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == name }) else { return }
        expenseNames.append(name)
        newExpenseName = ""
    }

    private func deleteExpenseNames(at offsets: IndexSet) {
        expenseNames.remove(atOffsets: offsets)
    }
}

private struct FinancialSettlementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(BaseCurrencyCatalog.countryCodeKey) private var baseCurrencyCountry = BaseCurrencyCatalog.defaultCountryCode
    @Bindable var booking: TripBookingRecord
    @State private var tripFare: Double
    @State private var tip: Double
    @State private var expenseAdjustments: [TripExpenseAdjustment]
    @State private var expenseItemNames: [String]
    @State private var errorMessage: String?

    private var currencySymbol: String {
        BaseCurrencyCatalog.option(for: baseCurrencyCountry).symbol
    }

    private var netIncome: Double {
        tripFare + tip + expenseAdjustments.reduce(0) { total, item in
            total + (item.isAddition ? abs(item.amount) : -abs(item.amount))
        }
    }

    init(booking: TripBookingRecord) {
        self.booking = booking
        _tripFare = State(initialValue: booking.price)
        _tip = State(initialValue: booking.tip)
        _expenseAdjustments = State(initialValue: booking.expenseAdjustments)
        _expenseItemNames = State(initialValue: ExpenseItemCatalog.load())
    }

    var body: some View {
        Form {
            Section("行程信息") {
                LabeledContent("客户", value: booking.customerName.isEmpty ? "未填写" : booking.customerName)
                LabeledContent("行程类型", value: booking.serviceType)
                LabeledContent("接载时间", value: appointmentDateTime.formatted(date: .abbreviated, time: .shortened))
                routeSummary
                if !booking.flightInfo.isEmpty {
                    LabeledContent("航班", value: booking.flightInfo)
                }
            }

            Section("财务信息") {
                HStack(spacing: 8) {
                    amountField("行程费用", amount: $tripFare)
                    Spacer(minLength: 4)
                    amountField("小费", amount: $tip)
                }
            }

            Section {
                ForEach(expenseAdjustments.indices, id: \.self) { index in
                    expenseRow($expenseAdjustments[index]) {
                        expenseAdjustments.remove(at: index)
                    }
                }

                Button {
                    expenseAdjustments.append(TripExpenseAdjustment())
                } label: {
                    Label("增加费用", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("费用明细")
            } footer: {
                Text("每行选择增加或扣减，净收入会自动按行程费用 + 小费 ± 费用明细计算。")
            }

            Section {
                HStack {
                    Text("净收入")
                        .font(.headline)
                    Spacer()
                    Text(BaseCurrencyCatalog.format(netIncome, countryCode: baseCurrencyCountry))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(netIncome >= 0 ? Color.primary : Color.red)
                }
                .padding(.vertical, 4)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("财务结算")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { saveSettlement() }
                    .fontWeight(.semibold)
            }
        }
        .alert("无法保存结算", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var appointmentDateTime: Date {
        let date = Calendar.current.dateComponents([.year, .month, .day], from: booking.appointmentDate)
        let time = Calendar.current.dateComponents([.hour, .minute], from: booking.appointmentTime)
        return Calendar.current.date(from: DateComponents(
            year: date.year, month: date.month, day: date.day,
            hour: time.hour, minute: time.minute
        )) ?? booking.appointmentDate
    }

    private var routeSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("行程路线")
                .foregroundStyle(.secondary)
            Text(([booking.locationStart] + booking.locationStops + [booking.locationEnd])
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " → "))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }

    private func amountField(_ title: String, amount: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Text(currencySymbol)
                .font(.headline)
                .foregroundStyle(.secondary)
            AmountTextField(placeholder: "0", value: amount, fontSize: 20)
                .frame(width: 76)
        }
    }

    private func expenseRow(
        _ expense: Binding<TripExpenseAdjustment>,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Button {
                expense.wrappedValue.isAddition.toggle()
            } label: {
                Text(expense.wrappedValue.isAddition ? "+" : "−")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(expense.wrappedValue.isAddition ? Color.green : Color.red)
                    .frame(width: 34, height: 34)
                    .background((expense.wrappedValue.isAddition ? Color.green : Color.red).opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expense.wrappedValue.isAddition ? "改为扣减" : "改为增加")

            Menu {
                ForEach(expenseItemNames, id: \.self) { name in
                    Button(name) { expense.wrappedValue.title = name }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(expense.wrappedValue.title.isEmpty ? "费用项目" : expense.wrappedValue.title)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(expense.wrappedValue.title.isEmpty ? Color.secondary : Color.primary)
            }
            .frame(minWidth: 90, alignment: .leading)

            Text(currencySymbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            AmountTextField(placeholder: "金额", value: expense.amount)
                .frame(width: 72)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 19))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除费用项目")
        }
    }

    private func saveSettlement() {
        guard tripFare >= 0, tip >= 0 else {
            errorMessage = "行程费用和小费不能小于 0。"
            return
        }

        let meaningfulItems = expenseAdjustments.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.amount != 0
        }
        guard meaningfulItems.allSatisfy({
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.amount > 0
        }) else {
            errorMessage = "请为每条费用明细填写项目名称和大于 0 的金额。"
            return
        }

        booking.price = max(0, tripFare)
        booking.tip = max(0, tip)
        booking.expenseAdjustments = meaningfulItems
        booking.isPaid = true
        booking.updatedAt = .now
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TripBrowseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @AppStorage(BaseCurrencyCatalog.countryCodeKey) private var baseCurrencyCountry = BaseCurrencyCatalog.defaultCountryCode
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Bindable var booking: TripBookingRecord
    @State private var activeTripForm: TripFormPresentation?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingCancellation = false
    @State private var isShowingCompletionSettlementPrompt = false
    @State private var isShowingFinancialSettlement = false
    @State private var isFlightExpanded = false
    @State private var isLookingUpFlight = false
    @State private var flightLookupResult: VariFlightLookupResult?
    @State private var flightLookupError: String?
    @State private var departureTimeZoneLabel = ""
    @State private var arrivalTimeZoneLabel = ""
    @State private var errorMessage: String?

    private var appointmentDateTime: Date {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: booking.appointmentDate)
        let time = Calendar.current.dateComponents([.hour, .minute], from: booking.appointmentTime)
        return Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute)) ?? booking.appointmentDate
    }

    private var compactOrderDetails: some View {
        HStack(spacing: 6) {
            compactDetail("行程类型", value: valueOrFallback(booking.serviceType))
            compactDetail("订单来源", value: valueOrFallback(booking.orderSource))
            compactDetail("乘客人数", value: passengerCountLabel(booking.customerCount))
            compactDetail("行李数量", value: baggageCountLabel(booking.customerStuff))
        }
    }

    private func passengerCountLabel(_ rawCount: String) -> String {
        let count = Int(rawCount) ?? 0
        return switch locale.language.languageCode?.identifier {
        case "en": count == 1 ? "1 passenger" : "\(count) passengers"
        case "es": count == 1 ? "1 pasajero" : "\(count) pasajeros"
        case "ja": "\(count) 人"
        case "ko": "\(count)명"
        case "zh" where locale.identifier.contains("Hant") || locale.identifier.contains("TW") || locale.identifier.contains("HK"):
            "\(count) 位乘客"
        default: "\(count) 位乘客"
        }
    }

    private func baggageCountLabel(_ rawCount: String) -> String {
        let count = Int(rawCount) ?? 0
        return switch locale.language.languageCode?.identifier {
        case "en": count == 1 ? "1 bag" : "\(count) bags"
        case "es": count == 1 ? "1 maleta" : "\(count) maletas"
        case "ja": "\(count) 個の荷物"
        case "ko": "\(count)개 수하물"
        case "zh" where locale.identifier.contains("Hant") || locale.identifier.contains("TW") || locale.identifier.contains("HK"):
            "\(count) 件行李"
        default: "\(count) 件行李"
        }
    }

    private var netIncome: Double {
        booking.price + booking.tip + booking.expenseAdjustments.reduce(0) { total, item in
            total + (item.isAddition ? abs(item.amount) : -abs(item.amount))
        }
    }

    private func detailStatusBadge(title: String, isOn: Bool, tint: Color) -> some View {
        Text(LocalizedStringKey(title))
            .font(.caption.weight(.semibold))
            .foregroundStyle(isOn ? tint : Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(isOn ? tint.opacity(0.13) : Color(.systemGroupedBackground), in: Capsule())
    }

    var body: some View {
        List {
            Section("订单信息") {
                LabeledContent("客户", value: valueOrFallback(booking.customerName))
                LabeledContent("联系方式", value: valueOrFallback(booking.customerContact))
                compactOrderDetails
                if booking.orderSource == "旅行社订单" {
                    HStack(spacing: 12) {
                        compactDetail("旅行社代码", value: valueOrFallback(booking.travelAgencyCode))
                        compactDetail("旅行社名称", value: valueOrFallback(booking.travelAgencyName))
                    }
                }
            }

            Section("时间") {
                LabeledContent("接载时间", value: appointmentDateTime.formatted(date: .long, time: .shortened))
            }

            Section("行程路线") {
                navigationAddressRow(title: "起始点", address: booking.locationStart)
                ForEach(Array(booking.locationStops.enumerated()), id: \.offset) { index, stop in
                    navigationAddressRow(title: "停靠点 \(index + 1)", address: stop)
                }
                navigationAddressRow(title: "目的地", address: booking.locationEnd)
            }

            if !booking.flightInfo.isEmpty {
                Section("航班信息") {
                    Button {
                        let shouldExpand = !isFlightExpanded
                        withAnimation(.easeInOut(duration: 0.2)) { isFlightExpanded = shouldExpand }
                        if shouldExpand && flightLookupResult == nil && !isLookingUpFlight { lookupFlight() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "airplane").foregroundStyle(Color.accentColor)
                            Text(booking.flightInfo).font(.subheadline.weight(.semibold))
                            Text(booking.flightDate, format: .dateTime.month(.abbreviated).day())
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if isLookingUpFlight { ProgressView().controlSize(.mini) }
                            else { Image(systemName: isFlightExpanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.tertiary) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if isFlightExpanded {
                        FlightInformationPanel(
                            flightNumber: booking.flightInfo,
                            flightDate: booking.flightDate,
                            result: flightLookupResult,
                            isLoading: isLookingUpFlight,
                            error: flightLookupError,
                            departureFallback: booking.flightDepartureTime ?? "",
                            arrivalFallback: booking.flightEstimatedArrivalTime ?? "",
                            departureTimeZone: departureTimeZoneLabel,
                            arrivalTimeZone: arrivalTimeZoneLabel
                        )
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            Section("状态") {
                HStack(spacing: 8) {
                    Text("行程状态")
                    detailStatusBadge(
                        title: booking.isCancelled ? "已取消" : (booking.isCompleted ? "已完成" : "待执行"),
                        isOn: booking.isCompleted || booking.isCancelled,
                        tint: booking.isCancelled ? .red : .accentColor
                    )
                    Spacer(minLength: 4)
                    Text("结算状态")
                    detailStatusBadge(title: booking.isPaid ? "已结清" : "未结款", isOn: booking.isPaid, tint: .green)
                }
                .font(.subheadline)
            }

            Section("财务结算信息") {
                HStack(spacing: 8) {
                    inlineFinancialDetail("行程费用", value: BaseCurrencyCatalog.format(booking.price, countryCode: baseCurrencyCountry))
                    Spacer(minLength: 4)
                    inlineFinancialDetail("小费", value: BaseCurrencyCatalog.format(booking.tip, countryCode: baseCurrencyCountry))
                }
                if booking.expenseAdjustments.isEmpty {
                    Text("暂无费用明细")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(booking.expenseAdjustments) { item in
                        HStack {
                            Text(item.title.isEmpty ? "费用项目" : item.title)
                            Spacer()
                            Text(item.isAddition ? "+" : "−")
                                .foregroundStyle(item.isAddition ? Color.green : Color.red)
                            Text(BaseCurrencyCatalog.format(abs(item.amount), countryCode: baseCurrencyCountry))
                        }
                    }
                }
                LabeledContent("净收入", value: BaseCurrencyCatalog.format(netIncome, countryCode: baseCurrencyCountry))
                    .fontWeight(.semibold)
            }

            if booking.reminderEnabled {
                Section("行程提醒") {
                    if let reminderDateTime = booking.reminderDateTime {
                        LabeledContent("第一次提醒", value: reminderDateTime.formatted(date: .long, time: .shortened))
                    } else {
                        Label("第一次提醒时间未设置", systemImage: "bell.badge")
                            .foregroundStyle(.secondary)
                    }

                    if booking.hasSecondReminder {
                        if let secondReminderDateTime = booking.secondReminderDateTime {
                            LabeledContent("第二次提醒", value: secondReminderDateTime.formatted(date: .long, time: .shortened))
                        } else {
                            Label("第二次提醒时间未设置", systemImage: "bell.badge")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if booking.isCancelled || (!booking.isCompleted || !booking.isPaid) {
                Section("操作") {
                    HStack(spacing: 12) {
                        if booking.isCancelled {
                            Button("恢复行程") {
                                booking.isCancelled = false
                                booking.isCompleted = false
                                saveChanges()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.accentColor)
                        } else if !booking.isCompleted {
                            Button("已完成") {
                                booking.isCompleted = true
                                booking.isCancelled = false
                                saveChanges()
                                isShowingCompletionSettlementPrompt = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.accentColor)
                            Button("取消行程") { isConfirmingCancellation = true }
                                .buttonStyle(.bordered)
                                .tint(.red)
                        }
                        if !booking.isPaid {
                            Button("财务结算") {
                                isShowingFinancialSettlement = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
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
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { activeTripForm = .copy } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("复制行程")
                if !booking.isCompleted && !booking.isCancelled {
                    Button { activeTripForm = .edit } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("编辑行程")
                    Button(role: .destructive) { isConfirmingDelete = true } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("删除行程")
                }
            }
        }
        .sheet(item: $activeTripForm) { presentation in
            AddTripFormView(
                isPresented: Binding(
                    get: { activeTripForm != nil },
                    set: { if !$0 { activeTripForm = nil } }
                ),
                booking: booking,
                copying: presentation == .copy
            )
        }
        .alert("行程已结束", isPresented: $isShowingCompletionSettlementPrompt) {
            Button("否", role: .cancel) { }
            Button("是") { isShowingFinancialSettlement = true }
        } message: {
            Text("是否财务结算？")
        }
        .sheet(isPresented: $isShowingFinancialSettlement) {
            NavigationStack {
                FinancialSettlementView(booking: booking)
            }
        }
        .confirmationDialog("是否需要取消行程？", isPresented: $isConfirmingCancellation, titleVisibility: .visible) {
            Button("是，取消行程", role: .destructive) {
                booking.isCancelled = true
                booking.isCompleted = false
                saveChanges()
            }
            Button("否", role: .cancel) { }
        }
        .confirmationDialog("确定删除该行程？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteTrip() }
            Button("取消", role: .cancel) {}
        }
        .alert("删除失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func inlineFinancialDetail(_ title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(LocalizedStringKey(title))
                .font(.headline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.vertical, 3)
    }

    private func compactDetail(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
    }

    private func navigationAddressRow(title: String, address: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(LocalizedStringKey(title))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("未填写")
                    .foregroundStyle(.secondary)
            } else if booking.isCompleted {
                Text(address)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    private func lookupFlight() {
        isLookingUpFlight = true
        flightLookupError = nil
        Task {
            defer { isLookingUpFlight = false }
            do {
                let result = try await VariFlightClient().lookup(
                    flightNumber: booking.flightInfo,
                    flightDate: booking.flightDate
                )
                flightLookupResult = result
                departureTimeZoneLabel = await FlightTimeZoneResolver.label(for: result.departureAirport, date: booking.flightDate) ?? ""
                arrivalTimeZoneLabel = await FlightTimeZoneResolver.label(for: result.arrivalAirport, date: booking.flightDate) ?? ""
            } catch {
                flightLookupError = error.localizedDescription
            }
        }
    }

    private func valueOrFallback(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "未填写") : value
    }

    private func saveChanges() {
        booking.updatedAt = .now
        try? modelContext.save()
    }

    private func deleteTrip() {
        SupabaseDataSync.recordDeletion(table: "trips", id: booking.id.uuidString.lowercased(), context: modelContext)
        let reminderIDs = [
            "trip-reminder-\(booking.id.uuidString)-1",
            "trip-reminder-\(booking.id.uuidString)-2"
        ]
        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.removePendingNotificationRequests(withIdentifiers: reminderIDs)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: reminderIDs)
        modelContext.delete(booking)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum TripFormPresentation: String, Identifiable {
    case edit
    case copy

    var id: String { rawValue }
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
                .keyboardDoneToolbar()
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
                .keyboardDoneToolbar()
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
        .modelContainer(for: AppDataSchema.modelTypes, inMemory: true)
}
