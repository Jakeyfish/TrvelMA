import SwiftUI
import UserNotifications

/// Cloud-only home summary. It intentionally keeps its records in memory and
/// obtains them directly from the authenticated account repository.
struct CloudHomeDashboardView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @State private var directory = CloudTripDirectoryModel()
    @State private var hasLoadedAccount = false

    var body: some View {
        CloudTripScheduleView(directory: directory, showsDateControls: false)
        .task(id: "\(auth.isCloudAccount)|\(auth.currentEmail)") {
            hasLoadedAccount = false
            directory.clearForAccountChange()
            await directory.reloadTrips(using: auth)
            hasLoadedAccount = true
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, hasLoadedAccount, auth.isCloudAccount else { return }
            Task { await directory.reloadTrips(using: auth) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cloudTripsDidChange)) { _ in
            Task { await directory.reloadTrips(using: auth) }
        }
        .refreshable { await directory.reloadTrips(using: auth) }
    }
}

struct CloudTripDirectoryView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @State private var directory = CloudTripDirectoryModel()
    @State private var isAdding = false
    @State private var hasLoadedAccount = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("行程")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    Button { isAdding = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.accentColor, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(directory.isLoading)
                    .accessibilityLabel("新增行程")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)

                CloudTripScheduleView(directory: directory, showsDateControls: true)
                    .padding(.horizontal, 16)
            }
            .background(Color(.systemGroupedBackground))
            .adaptiveFormPresentation(isPresented: $isAdding) {
                NavigationStack { CloudTripEditor(directory: directory, trip: nil) }
            }
            .task(id: "\(auth.isCloudAccount)|\(auth.currentEmail)") {
                hasLoadedAccount = false
                directory.clearForAccountChange()
                await directory.reload(using: auth)
                hasLoadedAccount = true
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, hasLoadedAccount, auth.isCloudAccount else { return }
                Task { await directory.reload(using: auth) }
            }
            .alert("无法更新行程", isPresented: Binding(
                get: { directory.errorMessage != nil && !directory.trips.isEmpty },
                set: { if !$0 { directory.clearError() } }
            )) {
                Button("确定", role: .cancel) { directory.clearError() }
            } message: {
                Text(directory.errorMessage ?? "")
            }
        }
    }
}

/// Opens only the new-trip form when the add button comes from Home.
/// The directory data is still loaded so customer and agency pickers are ready,
/// but the user is not sent through a second trip-list page first.
struct CloudNewTripSheet: View {
    @Environment(AuthViewModel.self) private var auth
    @State private var directory = CloudTripDirectoryModel()
    @State private var hasLoaded = false

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded || directory.isLoading {
                    ProgressView("正在准备行程表单…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = directory.errorMessage {
                    ContentUnavailableView {
                        Label("无法加载行程资料", systemImage: "icloud.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") {
                            Task { await directory.reload(using: auth) }
                        }
                    }
                } else {
                    CloudTripEditor(directory: directory, trip: nil)
                }
            }
        }
        .task(id: "\(auth.isCloudAccount)|\(auth.currentEmail)") {
            hasLoaded = false
            directory.clearForAccountChange()
            await directory.reload(using: auth)
            hasLoaded = true
        }
    }
}

/// Cloud backed counterpart to `TripListDashboardView`. It uses the same
/// date strip, search, filters, section heading, and card rhythm as local data.
private struct CloudTripScheduleView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(AppLanguageSettings.self) private var languageSettings
    @Environment(\.locale) private var locale
    let directory: CloudTripDirectoryModel
    let showsDateControls: Bool
    @State private var searchText = ""
    @State private var selectedFilter: TripListFilter = .all
    @State private var selectedDate: Date?
    @AppStorage("tripList.selectedDateTimestamp") private var selectedDateTimestamp = Date.now.timeIntervalSince1970
    @State private var dateMode: TripDateMode = .sevenDays
    @State private var isShowingAllDates = true

    private var dateNavigationAnchor: Date {
        selectedDate ?? Date(timeIntervalSince1970: selectedDateTimestamp)
    }

    private var datesWithTrips: [Date] {
        let calendar = Calendar.current
        let trips = showsDateControls
            ? directory.trips
            : directory.trips.filter { !$0.isCancelled && !$0.isCompleted && calendar.startOfDay(for: $0.appointmentDate.cloudDate) >= calendar.startOfDay(for: .now) }
        return Array(Set(trips.map { calendar.startOfDay(for: $0.appointmentDate.cloudDate) })).sorted()
    }

    private var visibleTrips: [CloudOnlineRepository.CloudTripRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return directory.trips.filter { trip in
            let date = trip.appointmentDate.cloudDate
            let matchesStatus: Bool
            if !showsDateControls {
                matchesStatus = !trip.isCompleted && !trip.isCancelled && calendar.startOfDay(for: date) >= today
            } else {
                switch selectedFilter {
                case .pending: matchesStatus = !trip.isCompleted && !trip.isCancelled
                case .unpaid: matchesStatus = !trip.isPaid
                case .all: matchesStatus = true
                case .history: matchesStatus = calendar.startOfDay(for: date) < today
                }
            }
            guard matchesStatus else { return false }
            if !showsDateControls, !isShowingAllDates,
               let selectedDate, !calendar.isDate(date, inSameDayAs: selectedDate) { return false }
            if showsDateControls, let selectedDate,
               !calendar.isDate(date, inSameDayAs: selectedDate) { return false }
            guard !query.isEmpty else { return true }
            return [trip.customerName, trip.customerContact, trip.serviceType, trip.locationStart,
                    trip.stops.map(\.address).joined(separator: " "), trip.locationEnd, trip.flightInfo,
                    trip.orderSource, trip.memo]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted {
            let lhs = $0.appointmentDate.cloudDate
            let rhs = $1.appointmentDate.cloudDate
            if !calendar.isDate(lhs, inSameDayAs: rhs) { return lhs < rhs }
            return $0.appointmentTime.cloudDate < $1.appointmentTime.cloudDate
        }
    }

    private var searchPlaceholder: String {
        switch languageSettings.selectedLanguage {
        case .simplifiedChinese: "搜索客户、地点、航班"
        case .traditionalChinese: "搜尋客戶、地點或航班"
        case .english: "Search customers, locations, or flights"
        case .spanish: "Buscar clientes, lugares o vuelos"
        case .japanese: "顧客、場所、便名を検索"
        case .korean: "고객, 위치 또는 항공편 검색"
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

            if showsDateControls && dateMode == .month {
                DatePicker("选择日期", selection: Binding(
                    get: { selectedDate ?? dateNavigationAnchor },
                    set: {
                        let day = Calendar.current.startOfDay(for: $0)
                        selectedDate = day
                        selectedDateTimestamp = day.timeIntervalSince1970
                    }
                ), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(.accentColor)
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }

            dateNavigationStrip

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                SystemIMETextField(text: $searchText, placeholder: searchPlaceholder, capitalization: .none)
                    .id(languageSettings.identifier)
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
                        Button { selectedFilter = filter; selectedDate = nil } label: {
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
                Text("\(visibleTrips.count)").font(.caption).foregroundStyle(.secondary)
            }

            ScrollView(.vertical) {
                if directory.isLoading && directory.trips.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 100)
                } else if let error = directory.errorMessage, directory.trips.isEmpty {
                    ContentUnavailableView {
                        Label("无法载入行程", systemImage: "icloud.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重试") { Task { await directory.reload(using: auth) } }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                } else if visibleTrips.isEmpty {
                    ContentUnavailableView(
                        LocalizedStringKey(searchText.isEmpty ? "暂无行程" : "没有找到行程"),
                        systemImage: searchText.isEmpty ? "calendar" : "magnifyingglass",
                        description: Text(LocalizedStringKey(searchText.isEmpty ? "新增行程后会显示在这里。" : "请更换搜索内容或筛选条件。"))
                    ).padding(.vertical, 12)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(visibleTrips) { trip in
                            CloudTripManagementCard(
                                trip: trip,
                                directory: directory,
                                showsFlightActions: !trip.isCompleted && !trip.isCancelled
                            )
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
        }
        .font(.system(size: 14))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: datesWithTrips) { _, newDates in
            guard !showsDateControls, !isShowingAllDates,
                  !newDates.isEmpty, let firstDate = newDates.first,
                  selectedDate.map({ date in newDates.contains(where: { Calendar.current.isDate($0, inSameDayAs: date) }) }) == false
            else { return }
            selectedDate = firstDate
        }
    }

    private var allTripsButton: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let upcomingCount = directory.trips.filter { !$0.isCompleted && !$0.isCancelled && Calendar.current.startOfDay(for: $0.appointmentDate.cloudDate) >= today }.count
        let count = showsDateControls ? directory.trips.count : upcomingCount
        let selected = showsDateControls ? selectedDate == nil : isShowingAllDates
        return Button { isShowingAllDates = true; selectedDate = nil } label: {
            VStack(spacing: 3) {
                Text("全部").font(.system(size: 11, weight: .medium))
                Text("行程").font(.system(size: 15, weight: .bold, design: .rounded))
                Text(orderCountLabel(count)).font(.system(size: 10)).opacity(0.8)
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(width: 68, height: 66)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(selected ? Color.accentColor : Color(.secondarySystemGroupedBackground)))
        }.buttonStyle(.plain)
    }

    private var dateNavigationStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                allTripsButton
                ForEach(datesWithTrips, id: \.self) { date in
                    dateButton(for: date)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func dateButton(for date: Date) -> some View {
        let selected = showsDateControls
            ? selectedDate.map { Calendar.current.isDate(date, inSameDayAs: $0) } ?? false
            : !isShowingAllDates && selectedDate.map { Calendar.current.isDate(date, inSameDayAs: $0) } == true
        let title = Calendar.current.isDateInToday(date)
            ? String(localized: "今天", locale: locale)
            : Calendar.current.isDateInTomorrow(date)
                ? String(localized: "明天", locale: locale)
                : date.formatted(.dateTime.weekday(.wide).locale(locale))
        let count = directory.trips.filter {
            (showsDateControls || (!$0.isCompleted && !$0.isCancelled)) && Calendar.current.isDate($0.appointmentDate.cloudDate, inSameDayAs: date)
        }.count
        return Button {
            let day = Calendar.current.startOfDay(for: date)
            isShowingAllDates = false
            selectedDate = day
            selectedDateTimestamp = day.timeIntervalSince1970
        } label: {
            VStack(spacing: 3) {
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                Text(date.formatted(.dateTime.month(.twoDigits).day(.twoDigits).locale(locale))).font(.system(size: 15, weight: .bold, design: .rounded))
                Text(orderCountLabel(count)).font(.system(size: 10)).opacity(0.8)
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
        switch languageSettings.selectedLanguage {
        case .simplifiedChinese: "\(count) 单"
        case .traditionalChinese: "\(count) 單"
        case .english: count == 1 ? "1 order" : "\(count) orders"
        case .spanish: count == 1 ? "1 viaje" : "\(count) viajes"
        case .japanese: "\(count) 件"
        case .korean: "\(count)건"
        }
    }
}

private struct CloudTripManagementCard: View {
    @Environment(AppLanguageSettings.self) private var languageSettings
    @Environment(\.locale) private var locale
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.openURL) private var openURL
    @AppStorage(NavigationProvider.defaultsKey) private var defaultNavigationProvider = NavigationProvider.appleMaps.rawValue
    let trip: CloudOnlineRepository.CloudTripRecord
    let directory: CloudTripDirectoryModel
    var showsFlightActions = true
    @State private var isFlightExpanded = false
    @State private var isLookingUpFlight = false
    @State private var flightLookupResult: VariFlightLookupResult?
    @State private var flightCandidates: [VariFlightLookupResult] = []
    @State private var isChoosingFlight = false
    @State private var flightLookupError: String?
    @State private var departureTimeZoneLabel = ""
    @State private var arrivalTimeZoneLabel = ""
    @State private var isConfirmingCancellation = false
    @State private var isShowingCompletionPrompt = false
    @State private var isShowingSettlement = false

    private var appointmentDateTime: Date {
        let date = trip.appointmentDate.cloudDate
        let time = trip.appointmentTime.cloudDate
        var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        return Calendar.current.date(from: components) ?? date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink {
                CloudTripDetailView(trip: trip, directory: directory)
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 11) {
                        VStack(spacing: 4) {
                            Text(appointmentDateTime.formatted(.dateTime.hour().minute().locale(locale)))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                            Text(appointmentDateTime.formatted(.dateTime.month(.abbreviated).day().locale(locale)))
                                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        }
                        .frame(width: 72, height: 58)
                        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))

                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(trip.customerName.isEmpty ? String(localized: "未填写客户", locale: languageSettings.locale) : trip.customerName)
                                    .font(.headline.weight(.bold)).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(cloudMoney(trip.price, code: trip.currencyCode))
                                    .font(.headline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
                            }
                            Label(LocalizedStringKey(trip.serviceType), systemImage: serviceIcon)
                                .font(.subheadline.weight(.medium)).foregroundStyle(Color.accentColor)
                            HStack(spacing: 6) {
                                cloudInfoPill(count: trip.customerCount, singular: "passenger", plural: "passengers", icon: "person.fill", isBag: false)
                                cloudInfoPill(count: trip.customerStuff, singular: "bag", plural: "bags", icon: "suitcase.fill", isBag: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 7) {
                routeRow(title: "起始点", value: trip.locationStart, color: .teal, isLast: false, icon: "mappin.and.ellipse")
                ForEach(Array(trip.stops.enumerated()), id: \.element.id) { index, stop in
                routeRow(title: String(format: String(localized: "停靠点 %lld", locale: locale), locale: locale, index + 1), value: stop.address, color: .orange, isLast: false)
                }
                routeRow(title: "目的地", value: trip.locationEnd, color: .orange, isLast: true, icon: "flag.checkered")
            }

            if !trip.flightInfo.isEmpty && showsFlightActions { flightPanel }

            HStack(spacing: 8) {
                statusBadge(title: trip.isCancelled ? "已取消" : (trip.isCompleted ? "已完成" : "待执行"), isOn: trip.isCompleted || trip.isCancelled, tint: trip.isCancelled ? .red : Color.accentColor)
                statusBadge(title: trip.isPaid ? "已结清" : "未收款", isOn: trip.isPaid, tint: .green)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }

            if (!trip.isCompleted && !trip.isCancelled) || !trip.isPaid {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if !trip.isCompleted && !trip.isCancelled {
                        Button("已完成") {
                            Task {
                                if await directory.updateStatus(for: trip, isCompleted: true, isCancelled: false, using: auth) {
                                    isShowingCompletionPrompt = true
                                }
                            }
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12), in: Capsule()).buttonStyle(.plain)

                        Button("取消行程") { isConfirmingCancellation = true }
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.red)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.red.opacity(0.10), in: Capsule()).buttonStyle(.plain)
                    }
                    if !trip.isPaid {
                        Button("财务结算") { isShowingSettlement = true }
                            .font(.caption.weight(.semibold)).foregroundStyle(.green)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.green.opacity(0.12), in: Capsule()).buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        .confirmationDialog("是否需要取消行程？", isPresented: $isConfirmingCancellation, titleVisibility: .visible) {
            Button("是，取消行程", role: .destructive) {
                Task { _ = await directory.updateStatus(for: trip, isCompleted: false, isCancelled: true, using: auth) }
            }
            Button("否", role: .cancel) {}
        }
        .alert("行程已结束", isPresented: $isShowingCompletionPrompt) {
            Button("否", role: .cancel) {}
            Button("是") { isShowingSettlement = true }
        } message: {
            Text("是否财务结算？")
        }
        .adaptiveFormPresentation(isPresented: $isShowingSettlement) {
            NavigationStack { CloudTripEditor(directory: directory, trip: trip, settlementOnly: true) }
        }
        .adaptiveFormPresentation(isPresented: $isChoosingFlight) {
            FlightCandidatePicker(candidates: flightCandidates, onSelect: selectFlight)
        }
        .alert("无法更新行程", isPresented: Binding(
            get: { directory.errorMessage != nil },
            set: { if !$0 { directory.clearError() } }
        )) {
            Button("确定", role: .cancel) { directory.clearError() }
        } message: {
            Text(directory.errorMessage ?? "")
        }
    }

    private func cloudInfoPill(count rawCount: String, singular: String, plural: String, icon: String, isBag: Bool) -> some View {
        let count = Int(rawCount) ?? 0
        let label: String
        switch languageSettings.selectedLanguage {
        case .simplifiedChinese: label = isBag ? "\(count) 件行李" : "\(count) 位乘客"
        case .traditionalChinese: label = isBag ? "\(count) 件行李" : "\(count) 位乘客"
        case .english: label = "\(count) \(count == 1 ? singular : plural)"
        case .spanish: label = "\(count) \(singular == "bag" ? (count == 1 ? "maleta" : "maletas") : (count == 1 ? "pasajero" : "pasajeros"))"
        case .japanese: label = isBag ? "\(count) 個の荷物" : "\(count) 人"
        case .korean: label = isBag ? "\(count)개 수하물" : "\(count)명"
        }
        return Label(label, systemImage: icon)
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color(.systemGroupedBackground), in: Capsule())
    }

    private var serviceIcon: String {
        switch trip.serviceType {
        case "接机": "airplane.arrival"
        case "送机": "airplane.departure"
        case "接送", "包车": "car.fill"
        default: "figure.wave"
        }
    }

    private var flightPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "airplane").foregroundStyle(Color.accentColor)
                Text(trip.flightInfo).font(.subheadline.weight(.semibold))
                Text(trip.flightDate.cloudDate.formatted(.dateTime.month(.abbreviated).day().locale(locale)))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                            let shouldExpand = !isFlightExpanded
                            withAnimation(.easeInOut(duration: 0.2)) { isFlightExpanded = shouldExpand }
                    if shouldExpand && flightLookupResult == nil && !isLookingUpFlight { loadSavedFlightOrLookup() }
                } label: {
                    HStack(spacing: 5) {
                            if isLookingUpFlight { ProgressView().controlSize(.mini) }
                        Text(LocalizedStringKey("航班")).font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                        Image(systemName: isFlightExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                }.buttonStyle(.plain)
                Button { lookupFlight() } label: {
                    Image(systemName: "arrow.clockwise").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain).disabled(isLookingUpFlight).accessibilityLabel("刷新航班信息")
            }
            .padding(10)

            if isFlightExpanded {
                flightDetails
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var flightDetails: some View {
        FlightInformationPanel(
            flightNumber: trip.flightInfo,
            flightDate: trip.flightDate.cloudDate,
            result: flightLookupResult,
            isLoading: isLookingUpFlight,
            error: flightLookupError,
            departureFallback: trip.flightDepartureTime ?? "",
            arrivalFallback: trip.flightEstimatedArrivalTime ?? "",
            departureTimeZone: departureTimeZoneLabel,
            arrivalTimeZone: arrivalTimeZoneLabel
        )
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func lookupFlight() {
        guard !trip.flightInfo.isEmpty else { return }
        isLookingUpFlight = true
        flightLookupError = nil
        Task {
            do {
                let date = trip.flightDate.cloudDate
                let accessToken = await auth.refreshCloudAccessToken() ?? auth.cloudAccessToken
                guard let accessToken else { throw VariFlightClientError.missingCloudSession }
                let candidates = try await VariFlightClient().lookupCandidatesForTrip(
                    flightNumber: trip.flightInfo,
                    flightDate: date,
                    serviceType: trip.serviceType,
                    locationStart: trip.locationStart,
                    locationEnd: trip.locationEnd,
                    cloudAccessToken: accessToken
                )
                flightCandidates = candidates
                isChoosingFlight = true
            } catch {
                flightLookupError = error.localizedDescription
            }
            isLookingUpFlight = false
        }
    }

    private func loadSavedFlightOrLookup() {
        if let saved = trip.flightSelectionSnapshot,
           saved.matches(flightNumber: trip.flightInfo, flightDate: trip.flightDate.cloudDate) {
            flightLookupResult = saved.selected
            return
        }
        lookupFlight()
    }

    private func selectFlight(_ result: VariFlightLookupResult) {
        flightLookupResult = result
        let saved = SavedFlightSelection(flightNumber: trip.flightInfo, flightDate: trip.flightDate.cloudDate, selected: result)
        departureTimeZoneLabel = ""
        arrivalTimeZoneLabel = ""
        Task {
            let departureZone = await FlightTimeZoneResolver.label(for: result.departureAirport, date: trip.flightDate.cloudDate) ?? ""
            let arrivalZone = await FlightTimeZoneResolver.label(for: result.arrivalAirport, date: trip.flightDate.cloudDate) ?? ""
            departureTimeZoneLabel = departureZone
            arrivalTimeZoneLabel = arrivalZone
            _ = await directory.updateStatus(for: trip, flightSelectionSnapshot: saved, using: auth)
        }
    }

    private func routeRow(title: String, value: String, color: Color, isLast: Bool, icon: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(color).frame(width: 16, height: 16)
                } else {
                    Circle().fill(color).frame(width: 9, height: 9).frame(width: 16, height: 16)
                }
                if !isLast { Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 2, height: 23) }
            }
            NavigationLink {
                CloudTripDetailView(trip: trip, directory: directory)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
                    Text(value.isEmpty ? String(localized: "未填写", locale: languageSettings.locale) : value)
                        .font(.subheadline.weight(.medium)).foregroundStyle(value.isEmpty ? Color.secondary : Color.primary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                let provider = NavigationProvider(rawValue: defaultNavigationProvider) ?? .appleMaps
                if let url = provider.directionsURL(for: value) { openURL(url) }
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.35) : Color.accentColor)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("导航至\(title)")
        }
    }

    private func statusBadge(title: String, isOn: Bool, tint: Color) -> some View {
        Text(LocalizedStringKey(title)).font(.caption.weight(.semibold))
            .foregroundStyle(isOn ? tint : Color.secondary)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(isOn ? tint.opacity(0.13) : Color(.systemGroupedBackground), in: Capsule())
    }
}

private struct CloudTripRow: View {
    let trip: CloudOnlineRepository.CloudTripRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(trip.customerName.isEmpty ? "未填写客户" : trip.customerName)
                    .font(.headline).lineLimit(1)
                Spacer()
                Text(cloudMoney(trip.price + trip.tip, code: trip.currencyCode))
                    .font(.subheadline.weight(.semibold))
            }
            HStack(spacing: 8) {
                Text(trip.serviceType)
                Text("·")
                Text(trip.appointmentDate.cloudDateText)
                if !trip.flightInfo.isEmpty { Text("· \(trip.flightInfo)") }
            }
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text("\(trip.locationStart) → \(trip.locationEnd)")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

private struct CloudTripDetailView: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @AppStorage(NavigationProvider.defaultsKey) private var defaultNavigationProvider = NavigationProvider.appleMaps.rawValue
    @State private var isLookingUpFlight = false
    @State private var flightLookupResult: VariFlightLookupResult?
    @State private var flightLookupError: String?
    @State private var departureTimeZoneLabel = ""
    @State private var arrivalTimeZoneLabel = ""
    let trip: CloudOnlineRepository.CloudTripRecord
    let directory: CloudTripDirectoryModel
    @State private var isEditing = false
    @State private var isCopying = false
    @State private var isConfirmingDelete = false
    @State private var isConfirmingCancellation = false
    @State private var isShowingCompletionPrompt = false
    @State private var isShowingSettlement = false
    @State private var isFlightExpanded = false

    private var netIncome: Double {
        trip.price + trip.tip + trip.expenses.reduce(0) { $0 + ($1.isAddition ? abs($1.amount) : -abs($1.amount)) }
    }

    private var appointmentDateTime: Date {
        let date = trip.appointmentDate.cloudDate
        let time = trip.appointmentTime.cloudDate
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let clock = Calendar.current.dateComponents([.hour, .minute], from: time)
        return Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: clock.hour, minute: clock.minute)) ?? date
    }

    private var statusSection: some View {
        Section("状态") {
            HStack(spacing: 8) {
                Text("行程状态")
                detailStatusBadge(title: tripStatusTitle, isOn: trip.isCompleted || trip.isCancelled, tint: trip.isCancelled ? .red : .accentColor)
                Spacer(minLength: 4)
                Text("结算状态")
                detailStatusBadge(title: trip.isPaid ? "已结清" : "未结款", isOn: trip.isPaid, tint: .green)
            }.font(.subheadline)
        }
    }

    private var tripStatusTitle: String {
        if trip.isCancelled { return "已取消" }
        return trip.isCompleted ? "已完成" : "待执行"
    }

    @ViewBuilder
    private var tripActionsSection: some View {
        if trip.isCancelled || !trip.isCompleted || !trip.isPaid {
            Section("操作") {
                HStack(spacing: 12) {
                    if trip.isCancelled {
                        Button("恢复行程") {
                            Task { _ = await directory.updateStatus(for: trip, isCompleted: false, isCancelled: false, using: auth) }
                        }.buttonStyle(.borderedProminent)
                    } else if !trip.isCompleted {
                        Button("已完成") {
                            Task {
                                if await directory.updateStatus(for: trip, isCompleted: true, isCancelled: false, using: auth) {
                                    isShowingCompletionPrompt = true
                                }
                            }
                        }.buttonStyle(.borderedProminent)
                        Button("取消行程") { isConfirmingCancellation = true }
                            .buttonStyle(.bordered).tint(.red)
                    }
                    if !trip.isPaid {
                        Button("财务结算") { isShowingSettlement = true }
                            .buttonStyle(.borderedProminent).tint(.green)
                    }
                }.frame(maxWidth: .infinity)
            }
        }
    }

    var body: some View {
        List {
            Section("订单信息") {
                LabeledContent("客户", value: valueOrFallback(trip.customerName))
                LabeledContent("联系方式", value: valueOrFallback(trip.customerContact))
                HStack(spacing: 8) {
                    compactDetail("行程类型", value: trip.serviceType)
                    compactDetail("订单来源", value: trip.orderSource)
                    compactDetail("乘客人数", value: passengerCountLabel(trip.customerCount))
                    compactDetail("行李数量", value: baggageCountLabel(trip.customerStuff))
                }
                if trip.orderSource == "旅行社订单" {
                    HStack(spacing: 12) {
                        compactDetail("旅行社代码", value: trip.travelAgencyCode.isEmpty ? "未填写" : trip.travelAgencyCode)
                        compactDetail("旅行社名称", value: trip.travelAgencyName.isEmpty ? "未填写" : trip.travelAgencyName)
                    }
                }
            }
            Section("时间") {
                LabeledContent("接载时间", value: appointmentDateTime.formatted(date: .long, time: .shortened))
            }
            Section("行程路线") {
                navigationAddressRow(title: "起始点", address: trip.locationStart)
                ForEach(trip.stops) { stop in
                    let number = stop.position + 1
                    let titleFormat = String(localized: "停靠点 %lld", locale: locale)
                    let title = String(format: titleFormat, locale: locale, arguments: [number])
                    navigationAddressRow(title: title, address: stop.address)
                }
                navigationAddressRow(title: "目的地", address: trip.locationEnd)
            }
            if !trip.flightInfo.isEmpty {
                Section("航班信息") {
                    Button {
                        let shouldExpand = !isFlightExpanded
                        withAnimation(.easeInOut(duration: 0.2)) { isFlightExpanded = shouldExpand }
                        if shouldExpand && flightLookupResult == nil && !isLookingUpFlight { lookupFlight() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "airplane").foregroundStyle(Color.accentColor)
                            Text(trip.flightInfo).font(.subheadline.weight(.semibold))
                            Text(trip.flightDate.cloudDate.formatted(.dateTime.month(.abbreviated).day().locale(locale)))
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            if isLookingUpFlight { ProgressView().controlSize(.mini) }
                            else { Image(systemName: isFlightExpanded ? "chevron.up" : "chevron.down").font(.caption).foregroundStyle(.tertiary) }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if isFlightExpanded {
                        FlightInformationPanel(
                            flightNumber: trip.flightInfo,
                            flightDate: trip.flightDate.cloudDate,
                            result: flightLookupResult,
                            isLoading: isLookingUpFlight,
                            error: flightLookupError,
                            departureFallback: trip.flightDepartureTime ?? "",
                            arrivalFallback: trip.flightEstimatedArrivalTime ?? "",
                            departureTimeZone: departureTimeZoneLabel,
                            arrivalTimeZone: arrivalTimeZoneLabel
                        )
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }
            statusSection
            Section("费用与收款") {
                HStack(spacing: 8) {
                    inlineFinancialDetail("行程费用", value: cloudMoney(trip.price, code: trip.currencyCode))
                    Spacer(minLength: 4)
                    inlineFinancialDetail("小费", value: cloudMoney(trip.tip, code: trip.currencyCode))
                }
                if trip.expenses.isEmpty {
                    Text("暂无费用明细").foregroundStyle(.secondary)
                }
                ForEach(trip.expenses) { item in
                    HStack {
                        Text(item.title.isEmpty ? "费用项目" : item.title)
                        Spacer()
                        Text(item.isAddition ? "+" : "−").foregroundStyle(item.isAddition ? Color.green : Color.red)
                        Text(cloudMoney(abs(item.amount), code: trip.currencyCode))
                    }
                }
                LabeledContent("净收入", value: cloudMoney(netIncome, code: trip.currencyCode)).fontWeight(.semibold)
            }
            if trip.reminderEnabled {
                Section("行程提醒") {
                    if let reminder = trip.reminderAt { LabeledContent("第一次提醒", value: reminder.cloudDate.formatted(date: .long, time: .shortened)) }
                    else { Label("第一次提醒时间未设置", systemImage: "bell.badge").foregroundStyle(.secondary) }
                    if trip.hasSecondReminder {
                        if let reminder = trip.secondReminderAt { LabeledContent("第二次提醒", value: reminder.cloudDate.formatted(date: .long, time: .shortened)) }
                        else { Label("第二次提醒时间未设置", systemImage: "bell.badge").foregroundStyle(.secondary) }
                    }
                }
            }
            tripActionsSection
            if !trip.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("备注") { Text(trip.memo).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .navigationTitle("行程详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { isCopying = true } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("复制行程")
                if !trip.isCompleted && !trip.isCancelled {
                    Button { isEditing = true } label: { Image(systemName: "pencil") }.accessibilityLabel("编辑行程")
                    Button(role: .destructive) { isConfirmingDelete = true } label: { Image(systemName: "trash") }.accessibilityLabel("删除行程")
                }
            }
        }
        .adaptiveFormPresentation(isPresented: $isEditing) {
            NavigationStack { CloudTripEditor(directory: directory, trip: trip) }
        }
        .adaptiveFormPresentation(isPresented: $isCopying) {
            NavigationStack { CloudTripEditor(directory: directory, trip: trip, copyAsNew: true) }
        }
        .confirmationDialog("确定删除该行程？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    if await directory.delete(id: trip.id, using: auth) {
                        if let tripUUID = UUID(uuidString: trip.id) {
                            let identifiers = [
                                "trip-reminder-\(tripUUID.uuidString)-1",
                                "trip-reminder-\(tripUUID.uuidString)-2"
                            ]
                            let center = UNUserNotificationCenter.current()
                            center.removePendingNotificationRequests(withIdentifiers: identifiers)
                            center.removeDeliveredNotifications(withIdentifiers: identifiers)
                        }
                        dismiss()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("是否需要取消行程？", isPresented: $isConfirmingCancellation, titleVisibility: .visible) {
            Button("是，取消行程", role: .destructive) { Task { _ = await directory.updateStatus(for: trip, isCompleted: false, isCancelled: true, using: auth) } }
            Button("否", role: .cancel) {}
        }
        .alert("行程已结束", isPresented: $isShowingCompletionPrompt) {
            Button("否", role: .cancel) {}
            Button("是") { isShowingSettlement = true }
        } message: { Text("是否财务结算？") }
        .adaptiveFormPresentation(isPresented: $isShowingSettlement) {
            NavigationStack { CloudTripEditor(directory: directory, trip: trip, settlementOnly: true) }
        }
        .alert("无法删除行程", isPresented: Binding(
            get: { directory.errorMessage != nil },
            set: { if !$0 { directory.clearError() } }
        )) {
            Button("确定", role: .cancel) { directory.clearError() }
        } message: {
            Text(directory.errorMessage ?? "")
        }
    }

    private func detailStatusBadge(title: String, isOn: Bool, tint: Color) -> some View {
        Text(LocalizedStringKey(title)).font(.caption.weight(.semibold)).foregroundStyle(isOn ? tint : Color.secondary)
            .padding(.horizontal, 9).padding(.vertical, 6).background(isOn ? tint.opacity(0.13) : Color(.systemGroupedBackground), in: Capsule())
    }

    private func navigationAddressRow(title: String, address: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
            if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("未填写").foregroundStyle(.secondary)
            } else if trip.isCompleted {
                Text(address).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button {
                    let provider = NavigationProvider(rawValue: defaultNavigationProvider) ?? .appleMaps
                    if let url = provider.directionsURL(for: address) { openURL(url) }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(address).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").foregroundStyle(Color.accentColor)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.padding(.vertical, 3)
    }

    private func compactDetail(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title)).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
    }

    private func valueOrFallback(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(localized: "未填写", locale: locale) : value
    }

    private func inlineFinancialDetail(_ title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(LocalizedStringKey(title)).font(.headline).foregroundStyle(.secondary).fixedSize(horizontal: true, vertical: false)
            Text(value).font(.title3.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
        }.fixedSize(horizontal: true, vertical: false).padding(.vertical, 3)
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

    private func lookupFlight() {
        guard let saved = trip.flightSelectionSnapshot,
              saved.matches(flightNumber: trip.flightInfo, flightDate: trip.flightDate.cloudDate) else { return }
        flightLookupResult = saved.selected
        Task {
            departureTimeZoneLabel = await FlightTimeZoneResolver.label(for: saved.selected.departureAirport, date: trip.flightDate.cloudDate) ?? ""
            arrivalTimeZoneLabel = await FlightTimeZoneResolver.label(for: saved.selected.arrivalAirport, date: trip.flightDate.cloudDate) ?? ""
        }
    }
}

@MainActor
private struct CloudTripEditor: View {
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var appLocale
    @AppStorage(NavigationProvider.defaultsKey) private var defaultNavigationProvider = NavigationProvider.appleMaps.rawValue
    @State private var isLookingUpFlight = false
    @State private var flightLookupResult: VariFlightLookupResult?
    @State private var flightLookupError: String?
    @State private var flightCandidates: [VariFlightLookupResult] = []
    @State private var isChoosingFlight = false
    @State private var flightSelectionSnapshot: SavedFlightSelection?
    @State private var departureTimeZoneLabel = ""
    @State private var arrivalTimeZoneLabel = ""
    @StateObject private var locationManager = TripCurrentLocationManager()
    let directory: CloudTripDirectoryModel
    let trip: CloudOnlineRepository.CloudTripRecord?
    private let settlementOnly: Bool
    private let copyAsNew: Bool

    @State private var serviceType: String
    @State private var orderSource: String
    @State private var customerID: String
    @State private var customerName: String
    @State private var customerContact: String
    @State private var agencyCode: String
    @State private var agencyName: String
    @State private var customerCount: String
    @State private var customerStuff: String
    @State private var appointmentDate: Date
    @State private var appointmentTime: Date
    @State private var start: String
    @State private var stops: [String]
    @State private var destination: String
    @State private var flightNumber: String
    @State private var flightDate: Date
    @State private var departureTime: String
    @State private var estimatedArrivalTime: String
    @State private var terminal: String
    @State private var baggageCarousel: String
    @State private var price: String
    @State private var tip: String
    @State private var isPaid: Bool
    @State private var isCompleted: Bool
    @State private var isCancelled: Bool
    @State private var reminderEnabled: Bool
    @State private var reminderDate: Date
    @State private var hasSecondReminder: Bool
    @State private var secondReminderDate: Date
    @State private var memo: String
    @State private var expenses: [CloudTripExpenseDraft]
    @State private var addressSearchTarget: String?
    @StateObject private var addressSearcher = AddressAutocompleteSearcher()
    @State private var isShowingCustomerPicker = false
    @State private var isShowingAgencyPicker = false
    @State private var quickInputText = ""

    private let serviceTypes = ["接机", "送机", "接送", "包车", "转机", "其它"]

    private var moneySymbol: String {
        BaseCurrencyCatalog.options.first { $0.currencyCode == directory.currencyCode }?.symbol ?? "$"
    }

    private func serviceIcon(for type: String) -> String {
        switch type {
        case "接机": "airplane.departure"
        case "送机": "airplane.arrival"
        case "接送": "car.fill"
        case "包车": "clock.fill"
        default: "ellipsis.circle.fill"
        }
    }

    private func formCard<Content: View>(
        _ title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(LocalizedStringKey(title), systemImage: icon)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }

    private func labeledInput(
        _ title: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default,
        icon: String? = nil,
        prefix: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                Text(LocalizedStringKey(title))
            }
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let prefix {
                    Text(prefix).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    SystemIMETextField(
                        text: text,
                        placeholder: placeholder,
                        keyboardType: keyboard,
                        capitalization: title == "航班信息" ? .allCharacters : .sentences,
                        autocorrection: title == "航班信息" ? .no : .default,
                        textAlignment: .trailing,
                        fontSize: 14
                    )
                    .frame(width: numericTextFieldWidth(for: text.wrappedValue, placeholder: placeholder))
                    .padding(.vertical, 10)
                } else {
                    SystemIMETextField(
                        text: text,
                        placeholder: placeholder,
                        keyboardType: keyboard,
                        capitalization: title == "航班信息" ? .allCharacters : .sentences,
                        autocorrection: title == "航班信息" ? .no : .default,
                        fontSize: 14
                    )
                    .padding(10)
                }
            }
            .frame(maxWidth: .infinity, alignment: prefix == nil ? .leading : .trailing)
            .frame(minHeight: 44)
            .padding(.horizontal, prefix == nil ? 0 : 10)
            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledDate(
        _ title: String,
        date: Binding<Date>,
        components: DatePickerComponents,
        icon: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                Text(LocalizedStringKey(title))
            }
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            DatePicker(LocalizedStringKey(title), selection: date, displayedComponents: components)
                .labelsHidden().datePickerStyle(.compact).tint(.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(minHeight: 44)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reminderDateTimePickers(_ dateTime: Binding<Date>) -> some View {
        HStack(spacing: 10) {
            reminderDatePicker("日期", date: dateTime, component: .date)
            reminderDatePicker("时间", date: dateTime, component: .hourAndMinute)
        }
    }

    private func reminderDatePicker(_ title: String, date: Binding<Date>, component: DatePickerComponents) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title)).font(.caption2).foregroundStyle(.secondary)
            DatePicker(LocalizedStringKey(title), selection: date, displayedComponents: component)
                .labelsHidden().datePickerStyle(.compact).tint(.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).frame(minHeight: 42)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        }
    }

    private func setReminderEnabled(_ enabled: Bool) {
        guard enabled else {
            reminderEnabled = false
            return
        }
        Task {
            do {
                let allowed = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                if allowed {
                    updateReminderDefaults(copyDefault: copyAsNew)
                    reminderEnabled = true
                } else {
                    directory.setError(String(localized: "请在 iPhone 设置中允许行程管家发送通知。", locale: appLocale))
                }
            } catch {
                directory.setError(String(localized: "无法启用提醒，请稍后重试。", locale: appLocale))
            }
        }
    }

    private func agencyValueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title)).foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "点击选择" : value)
                .foregroundStyle(value.isEmpty ? Color.accentColor : Color.primary).lineLimit(1)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .font(.system(size: 13, weight: .medium))
    }

    private func addressEditor(_ title: String, value: Binding<String>, target: String, placeholder: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Label(LocalizedStringKey(title), systemImage: icon)
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            addressField(value, target: target, placeholder: placeholder)
                .padding(8)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        }
    }

    private func lookupFlight() {
        let normalizedNumber = flightNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedNumber.isEmpty else { return }
        let lookupDate = flightDate
        flightLookupResult = nil
        flightLookupError = nil
        isLookingUpFlight = true
        Task {
            defer { isLookingUpFlight = false }
            do {
                let accessToken = await auth.refreshCloudAccessToken() ?? auth.cloudAccessToken
                guard let accessToken else { throw VariFlightClientError.missingCloudSession }
                let candidates = try await VariFlightClient().lookupCandidatesForTrip(
                    flightNumber: normalizedNumber,
                    flightDate: lookupDate,
                    serviceType: serviceType,
                    locationStart: start,
                    locationEnd: destination,
                    cloudAccessToken: accessToken
                )
                flightCandidates = candidates
                isChoosingFlight = true
            } catch {
                flightLookupError = error.localizedDescription
            }
        }
    }

    private func selectFlight(_ result: VariFlightLookupResult) {
        flightLookupResult = result
        departureTime = result.departureTime ?? ""
        estimatedArrivalTime = result.estimatedArrivalTime ?? ""
        terminal = result.arrivalTerminal ?? ""
        baggageCarousel = result.baggageCarousel ?? ""
        flightSelectionSnapshot = SavedFlightSelection(flightNumber: flightNumber, flightDate: flightDate, selected: result)
        Task {
            departureTimeZoneLabel = await FlightTimeZoneResolver.label(for: result.departureAirport, date: flightDate) ?? ""
            arrivalTimeZoneLabel = await FlightTimeZoneResolver.label(for: result.arrivalAirport, date: flightDate) ?? ""
        }
    }

    init(directory: CloudTripDirectoryModel, trip: CloudOnlineRepository.CloudTripRecord?, settlementOnly: Bool = false, copyAsNew: Bool = false) {
        self.directory = directory
        self.trip = trip
        self.settlementOnly = settlementOnly
        self.copyAsNew = copyAsNew
        _serviceType = State(initialValue: trip?.serviceType ?? "接机")
        _orderSource = State(initialValue: trip?.orderSource ?? "普通客户")
        _customerID = State(initialValue: trip?.customerID ?? "")
        _customerName = State(initialValue: trip?.customerName ?? "")
        _customerContact = State(initialValue: trip?.customerContact ?? "")
        _agencyCode = State(initialValue: trip?.travelAgencyCode ?? "")
        _agencyName = State(initialValue: trip?.travelAgencyName ?? "")
        _customerCount = State(initialValue: trip?.customerCount ?? "1")
        _customerStuff = State(initialValue: trip?.customerStuff ?? "0")
        _appointmentDate = State(initialValue: copyAsNew ? .now : (trip?.appointmentDate.cloudDate ?? .now))
        _appointmentTime = State(initialValue: trip?.appointmentTime.cloudDate ?? .now)
        _start = State(initialValue: trip?.locationStart ?? "")
        _stops = State(initialValue: trip?.stops.map(\.address) ?? [])
        _destination = State(initialValue: trip?.locationEnd ?? "")
        _flightNumber = State(initialValue: trip?.flightInfo ?? "")
        _flightDate = State(initialValue: copyAsNew ? .now : (trip?.flightDate.cloudDate ?? .now))
        _flightSelectionSnapshot = State(initialValue: copyAsNew ? nil : trip?.flightSelectionSnapshot)
        _departureTime = State(initialValue: trip?.flightDepartureTime ?? "")
        _estimatedArrivalTime = State(initialValue: trip?.flightEstimatedArrivalTime ?? "")
        _terminal = State(initialValue: trip?.flightArrivalTerminal ?? "")
        _baggageCarousel = State(initialValue: trip?.flightBaggageCarousel ?? "")
        _price = State(initialValue: trip.map { String($0.price) } ?? "0")
        _tip = State(initialValue: copyAsNew ? "0" : (trip.map { String($0.tip) } ?? "0"))
        _isPaid = State(initialValue: copyAsNew ? false : (trip?.isPaid ?? false))
        _isCompleted = State(initialValue: copyAsNew ? false : (trip?.isCompleted ?? false))
        _isCancelled = State(initialValue: copyAsNew ? false : (trip?.isCancelled ?? false))
        _reminderEnabled = State(initialValue: copyAsNew ? true : (trip?.reminderEnabled ?? false))
        _reminderDate = State(initialValue: copyAsNew ? Date.now.addingTimeInterval(2 * 3600) : (trip?.reminderAt?.cloudDate ?? .now))
        _hasSecondReminder = State(initialValue: copyAsNew ? false : (trip?.hasSecondReminder ?? false))
        _secondReminderDate = State(initialValue: copyAsNew ? Date.now.addingTimeInterval(3600) : (trip?.secondReminderAt?.cloudDate ?? .now))
        _memo = State(initialValue: trip?.memo ?? "")
        _expenses = State(initialValue: copyAsNew ? [] : (trip?.expenses.map(CloudTripExpenseDraft.init) ?? []))
    }

    var body: some View {
        Group {
            if settlementOnly {
                Form { settlementForm }
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        formCard("行程类型", icon: "point.topleft.down.to.point.bottomright.curvepath") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                                ForEach(serviceTypes, id: \.self) { type in
                                    let selected = serviceType == type
                                    Button { serviceType = type } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: selected ? "checkmark.circle.fill" : serviceIcon(for: type))
                                                .foregroundStyle(selected ? Color.green : Color.secondary)
                                            Text(LocalizedStringKey(type)).lineLimit(1).minimumScaleFactor(0.75)
                                        }
                                        .font(.system(size: 13))
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.green.opacity(0.8) : Color.primary.opacity(0.14), lineWidth: selected ? 1.5 : 1))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }

                        formCard("智能粘贴", icon: "t.square") {
                            ZStack(alignment: .topLeading) {
                                LimitedIMETextEditor(text: $quickInputText, maxLength: 5000, fontSize: 14)
                                    .frame(minWidth: 0, maxWidth: .infinity).frame(height: 90).padding(10).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                                if quickInputText.isEmpty {
                                    Text("例如：明天晚上 9 点半 接机 UA123 张先生 送到市中心")
                                        .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
                                        .padding(.horizontal, 14).padding(.vertical, 16).allowsHitTesting(false)
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                                }
                            }
                        }

                        formCard("订单来源", icon: "tray.full") {
                            HStack(spacing: 12) {
                                orderSourceCard("普通客户", detail: "熟客、散客或临时客人。", icon: "person.fill")
                                orderSourceCard("旅行社订单", detail: "旅行社、地接或平台派单，记录订单号和联系人。", icon: "building.2.fill")
                            }
                        }

                        if orderSource == "旅行社订单" {
                            formCard("旅行社信息", icon: "building.2.fill") {
                                Button { isShowingAgencyPicker = true } label: {
                                    VStack(alignment: .leading, spacing: 10) {
                                        agencyValueRow("旅行社代码", value: agencyCode)
                                        Divider()
                                        agencyValueRow("旅行社名称", value: agencyName)
                                    }
                                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                                }.buttonStyle(.plain)
                            }
                        }

                        formCard("客户:", icon: "person.2") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("客户").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    TextField("请输入客户姓名", text: $customerName)
                                        .padding(12).frame(minHeight: 44)
                                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                                    Button { isShowingCustomerPicker = true } label: { Image(systemName: "person.crop.rectangle.badge.plus.fill") }
                                        .buttonStyle(.bordered).tint(.accentColor).accessibilityLabel("选择客户")
                                }
                            }
                            labeledInput("客户联系方式", placeholder: "请输入客户联系方式", text: $customerContact)
                            HStack(spacing: 10) {
                                labeledInput("人数", placeholder: "1", text: $customerCount, keyboard: .numberPad, icon: "person")
                                labeledInput("行李", placeholder: "0", text: $customerStuff, keyboard: .numberPad, icon: "suitcase")
                            }
                        }

                        formCard("行程详情", icon: "map") {
                            HStack(spacing: 12) {
                                labeledDate("接载日期", date: $appointmentDate, components: .date)
                                labeledDate("接载时间", date: $appointmentTime, components: .hourAndMinute)
                            }
                            HStack {
                                Label("起始点", systemImage: "mappin.and.ellipse")
                                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    let oldStart = start
                                    start = destination
                                    destination = oldStart
                                } label: {
                                    Label("互换", systemImage: "arrow.up.arrow.down")
                                        .font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                                }.buttonStyle(.plain)
                            }
                            addressEditor("", value: $start, target: "start", placeholder: "请输入客户的接载地点", icon: "mappin.and.ellipse")
                            ForEach(stops.indices, id: \.self) { index in
                                addressEditor("停靠点 \(index + 1)", value: $stops[index], target: "stop-\(index)", placeholder: "请输入停靠点", icon: "mappin")
                                    .overlay(alignment: .topTrailing) {
                                        Button(role: .destructive) { stops.remove(at: index) } label: { Image(systemName: "minus.circle.fill") }
                                            .offset(x: 5, y: -7)
                                    }
                            }
                            Button { stops.append("") } label: { Label("增加停靠点", systemImage: "plus.circle") }
                                .buttonStyle(.plain).foregroundStyle(Color.accentColor)
                            addressEditor("目的地", value: $destination, target: "destination", placeholder: "请输入目的地", icon: "flag.checkered")
                            Divider()
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("航班信息", systemImage: "airplane")
                                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    FlightNumberTextField(text: $flightNumber, placeholder: String(localized: "请输入航班号"), fontSize: 14)
                                        .padding(10)
                                        .frame(minHeight: 44)
                                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                                }
                                .frame(maxWidth: .infinity)
                                labeledDate("航班日期", date: $flightDate, components: .date, icon: "calendar")
                            }
                            Button(action: lookupFlight) {
                                HStack(spacing: 8) {
                                    if isLookingUpFlight { ProgressView().controlSize(.small) }
                                    else { Image(systemName: "magnifyingglass") }
                                    Text(isLookingUpFlight ? "正在查询航班" : "查询航班信息")
                                }.frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered).disabled(isLookingUpFlight || flightNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if isLookingUpFlight || flightLookupError != nil || flightLookupResult != nil {
                                FlightInformationPanel(
                                    flightNumber: flightNumber,
                                    flightDate: flightDate,
                                    result: flightLookupResult,
                                    isLoading: isLookingUpFlight,
                                    error: flightLookupError,
                                    departureFallback: departureTime,
                                    arrivalFallback: estimatedArrivalTime,
                                    departureTimeZone: departureTimeZoneLabel,
                                    arrivalTimeZone: arrivalTimeZoneLabel
                                )
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            }
                        }

                        formCard("费用与备注", icon: "dollarsign.circle") {
                            labeledInput("行程费用", placeholder: "0", text: $price, keyboard: .decimalPad, prefix: moneySymbol)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("备注").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                LimitedIMETextEditor(text: $memo, maxLength: 10000, fontSize: 14)
                                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 96).padding(8)
                                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                            }
                        }

                        formCard("状态信息", icon: "checkmark.circle") {
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("行程状态", systemImage: "clock").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    Text("待执行")
                                        .font(.caption.weight(.semibold)).foregroundStyle(Color.orange)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(Color.orange.opacity(0.12), in: Capsule())
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("结算状态", systemImage: "banknote").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    Picker("结算状态", selection: $isPaid) {
                                        Text("未结款").tag(false)
                                        Text("已结清").tag(true)
                                    }.pickerStyle(.segmented)
                                }.frame(maxWidth: .infinity)
                            }
                        }

                        formCard("提醒", icon: "bell.badge") {
                            Toggle(isOn: Binding(
                                get: { reminderEnabled },
                                set: { setReminderEnabled($0) }
                            )) { Text("自定义提醒").font(.subheadline) }.tint(.accentColor)
                            if reminderEnabled {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("提醒时间").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                    reminderDateTimePickers($reminderDate)
                                    Text(copyAsNew ? "默认：接载时间前 2 小时" : "默认：接载日期前一天的同一时间")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                                if hasSecondReminder {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text("第二次提醒").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                            Spacer()
                                            Button(role: .destructive) { hasSecondReminder = false } label: {
                                                Label("移除", systemImage: "minus.circle").font(.caption)
                                            }.buttonStyle(.plain)
                                        }
                                        reminderDateTimePickers($secondReminderDate)
                                        Text("默认：接载时间前 2 小时").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                } else {
                                    Button {
                                        hasSecondReminder = true
                                        updateSecondReminderDefault()
                                    } label: {
                                        Label("添加第二次提醒", systemImage: "plus.circle").font(.subheadline.weight(.medium))
                                    }.buttonStyle(.bordered).tint(.accentColor)
                                }
                            } else {
                                Text("开启后，行程管家会在设定时间发送系统通知。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 28)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Color.primary.opacity(0.015))
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(trip == nil || copyAsNew ? "新增行程" : "编辑行程")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { Task { await save() } }
                    .disabled(directory.isSaving)
            }
        }
        .overlay {
            if directory.isSaving { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) }
        }
        .alert("无法保存行程", isPresented: Binding(
            get: { directory.errorMessage != nil },
            set: { if !$0 { directory.clearError() } }
        )) {
            Button("确定", role: .cancel) { directory.clearError() }
        } message: {
            Text(directory.errorMessage ?? "")
        }
        .onChange(of: customerID) { _, id in
            if let customer = directory.customers.first(where: { $0.id == id }) {
                customerName = customer.name
                customerContact = customer.contacts.first(where: \.isDefault)?.value ?? customer.contacts.first?.value ?? customer.email
            }
        }
        .onChange(of: customerName) { _, value in
            guard let selected = directory.customers.first(where: { $0.id == customerID }),
                  value.trimmingCharacters(in: .whitespacesAndNewlines) != selected.name else { return }
            customerID = ""
        }
        .onChange(of: agencyCode) { _, code in
            guard let agency = directory.agencies.first(where: { $0.agencyCode == code }) else { return }
            agencyName = agency.name
        }
        .onAppear {
            if trip == nil || copyAsNew { updateReminderDefaults(copyDefault: copyAsNew) }
        }
        .onChange(of: appointmentDate) { _, _ in updateReminderDefaults(copyDefault: false) }
        .onChange(of: appointmentTime) { _, _ in updateReminderDefaults(copyDefault: false) }
        .onChange(of: locationManager.resolvedAddress) { _, address in
            guard let address, let target = addressSearchTarget else { return }
            switch target {
            case "start": start = address
            case "destination": destination = address
            default:
                if let index = Int(target.replacingOccurrences(of: "stop-", with: "")), stops.indices.contains(index) {
                    stops[index] = address
                }
            }
            addressSearchTarget = nil
        }
        .alert("无法获取当前位置", isPresented: Binding(
            get: { locationManager.errorMessage != nil },
            set: { if !$0 { locationManager.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { locationManager.errorMessage = nil }
        } message: {
            Text(locationManager.errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingCustomerPicker) {
            CloudTripCustomerSelectionView(customers: directory.customers, initialSelection: customerID) { customer in
                customerID = customer.id
                customerName = customer.name
                customerContact = customer.contacts.first(where: \.isDefault)?.value ?? customer.contacts.first?.value ?? customer.email
            }
        }
        .sheet(isPresented: $isShowingAgencyPicker) {
            CloudTripAgencySelectionView(agencies: directory.agencies) { agency in
                agencyCode = agency.agencyCode
                agencyName = agency.name
            }
        }
        .adaptiveFormPresentation(isPresented: $isChoosingFlight) {
            FlightCandidatePicker(candidates: flightCandidates, onSelect: selectFlight)
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var settlementForm: some View {
        Section("行程信息") {
            LabeledContent("客户", value: trip?.customerName.isEmpty == false ? trip!.customerName : "未填写")
            LabeledContent("行程类型", value: trip?.serviceType ?? serviceType)
            LabeledContent("接载时间", value: appointmentDate.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("行程路线", value: ([trip?.locationStart ?? start] + (trip?.stops.map(\.address) ?? stops) + [trip?.locationEnd ?? destination]).filter { !$0.isEmpty }.joined(separator: " → "))
            if let trip, !trip.flightInfo.isEmpty { LabeledContent("航班", value: trip.flightInfo) }
        }
        Section("财务信息") {
            SystemIMETextField(text: $price, placeholder: "行程费用", keyboardType: .decimalPad)
            SystemIMETextField(text: $tip, placeholder: "小费", keyboardType: .decimalPad)
        }
        Section {
            ForEach($expenses) { $expense in
                HStack(spacing: 8) {
                    Button { expense.isAddition.toggle() } label: {
                        Text(expense.isAddition ? "+" : "−").font(.title3.weight(.bold))
                            .foregroundStyle(expense.isAddition ? Color.green : Color.red).frame(width: 34, height: 34)
                            .background((expense.isAddition ? Color.green : Color.red).opacity(0.12), in: Circle())
                    }.buttonStyle(.plain)
                    TextField("费用项目", text: $expense.title)
                    SystemIMETextField(text: $expense.amount, placeholder: "金额", keyboardType: .decimalPad)
                        .frame(width: 78)
                    Button(role: .destructive) { expenses.removeAll { $0.id == expense.id } } label: { Image(systemName: "minus.circle.fill") }
                }
            }
            Button { expenses.append(CloudTripExpenseDraft()) } label: { Label("增加费用", systemImage: "plus.circle.fill") }
        } header: { Text("费用明细") }
          footer: { Text("每行选择增加或扣减，净收入 = 行程费用 + 小费 ± 费用明细。") }
        Section {
            HStack {
                Text("净收入").font(.headline)
                Spacer()
                Text(cloudMoney(settlementNetIncome, code: trip?.currencyCode ?? directory.currencyCode))
                    .font(.title3.weight(.bold)).foregroundStyle(settlementNetIncome >= 0 ? Color.primary : Color.red)
            }.padding(.vertical, 4)
        }
    }

    private func orderSourceCard(_ title: String, detail: String, icon: String) -> some View {
        let selected = orderSource == title
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                orderSource = title
                if !selected { agencyCode = ""; agencyName = "" }
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon).foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
                Text(LocalizedStringKey(title)).font(.system(size: 14, weight: .bold))
                Text(LocalizedStringKey(detail)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background(selected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.12), lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain)
    }

    private var settlementNetIncome: Double {
        (Double(price) ?? 0) + (Double(tip) ?? 0) + expenses.reduce(0) { $0 + ((Double($1.amount) ?? 0) * ($1.isAddition ? 1 : -1)) }
    }

    private func addressField(_ value: Binding<String>, target: String, placeholder: String = "输入地址，可搜索地点") -> some View {
        VStack(spacing: 4) {
            AddressSuggestionField(
                text: value,
                searcher: addressSearcher,
                placeholder: placeholder,
                isActive: addressSearchTarget == target,
                onFocus: { addressSearchTarget = target },
                onSelect: { selection in
                    value.wrappedValue = selection
                    addressSearcher.searchQuery = ""
                    addressSearchTarget = nil
                }
            )
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 38, alignment: .leading)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Menu {
                    if let customer = directory.customers.first(where: { $0.id == customerID }), !customer.addresses.isEmpty {
                        ForEach(customer.addresses) { address in
                            Button("\(address.label) · \(address.address)") { value.wrappedValue = address.address }
                        }
                    } else {
                        Text("所选客户没有常用地址")
                    }
                } label: { Image(systemName: "book.closed").frame(width: 34, height: 30) }
                .accessibilityLabel("选择客户常用地址")
                Button { addressSearchTarget = target; locationManager.requestCurrentLocation() } label: {
                    Image(systemName: "location.north.fill").frame(width: 34, height: 30)
                }.accessibilityLabel("获取当前位置")
                Button {
                    let provider = NavigationProvider(rawValue: defaultNavigationProvider) ?? .appleMaps
                    if let url = provider.directionsURL(for: value.wrappedValue) { openURL(url) }
                } label: { Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").frame(width: 34, height: 30) }
                    .disabled(value.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("导航至地址")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.accentColor)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func updateReminderDefaults(copyDefault: Bool) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: appointmentDate)
        let time = Calendar.current.dateComponents([.hour, .minute], from: appointmentTime)
        components.hour = time.hour
        components.minute = time.minute
        let appointment = Calendar.current.date(from: components) ?? appointmentDate
        let firstReminderHours = copyDefault ? -2 : -24
        reminderDate = Calendar.current.date(byAdding: .hour, value: firstReminderHours, to: appointment) ?? appointment
        secondReminderDate = Calendar.current.date(byAdding: .hour, value: -2, to: appointment) ?? appointment
    }

    private func updateSecondReminderDefault() {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: appointmentDate)
        let time = Calendar.current.dateComponents([.hour, .minute], from: appointmentTime)
        components.hour = time.hour
        components.minute = time.minute
        let appointment = Calendar.current.date(from: components) ?? appointmentDate
        secondReminderDate = Calendar.current.date(byAdding: .hour, value: -2, to: appointment) ?? appointment
    }

    private func save() async {
        guard !settlementOnly || trip != nil else { return }
        if settlementOnly {
            guard let fare = Double(price), fare >= 0, let tipAmount = Double(tip), tipAmount >= 0 else {
                directory.setError("行程费用和小费不能小于 0。")
                return
            }
            let meaningfulExpenses = expenses.filter {
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (Double($0.amount) ?? 0) != 0
            }
            guard meaningfulExpenses.allSatisfy({
                !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && (Double($0.amount) ?? 0) > 0
            }) else {
                directory.setError("请为每条费用明细填写项目名称和大于 0 的金额。")
                return
            }
        }
        if !settlementOnly && reminderEnabled {
            let reminderDates = hasSecondReminder ? [reminderDate, secondReminderDate] : [reminderDate]
            guard reminderDates.allSatisfy({ $0 > .now }) else {
                directory.setError("提醒时间必须晚于当前时间。")
                return
            }
        }
        let trimmedName = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !settlementOnly && trimmedName.isEmpty {
            directory.setError("请输入客户姓名后再保存行程。")
            return
        }
        let linkedCustomer = directory.customers.first(where: { $0.id == customerID })
        let id = copyAsNew ? UUID().uuidString.lowercased() : (trip?.id ?? UUID().uuidString.lowercased())
        let row: [String: Any] = [
            "id": id,
            "service_type": serviceType,
            "order_source": orderSource,
            "travel_agency_code": orderSource == "旅行社订单" ? agencyCode : "",
            "travel_agency_name": orderSource == "旅行社订单" ? agencyName : "",
            "customer_id": customerID.isEmpty ? NSNull() : customerID,
            "customer_name": linkedCustomer?.name ?? trimmedName,
            "customer_contact": linkedCustomer.map { $0.contacts.first(where: \.isDefault)?.value ?? $0.contacts.first?.value ?? $0.email } ?? customerContact,
            "customer_count": customerCount,
            "customer_stuff": customerStuff,
            "appointment_date": appointmentDate.cloudISO8601,
            "appointment_time": appointmentTime.cloudISO8601,
            "location_start": start,
            "location_end": destination,
            "flight_info": flightNumber.uppercased(),
            "flight_date": flightDate.cloudISO8601,
            "flight_departure_time": departureTime.isEmpty ? NSNull() : departureTime,
            "flight_estimated_arrival_time": estimatedArrivalTime.isEmpty ? NSNull() : estimatedArrivalTime,
            "flight_arrival_terminal": terminal.isEmpty ? NSNull() : terminal,
            "flight_baggage_carousel": baggageCarousel.isEmpty ? NSNull() : baggageCarousel,
            "flight_selection_snapshot": (!copyAsNew ? flightSelectionSnapshot ?? trip?.flightSelectionSnapshot : nil).map { snapshot in
                (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot))) ?? NSNull()
            } ?? NSNull(),
            "memo": String(memo.prefix(2048)),
            "price": Double(price) ?? 0,
            "tip": Double(tip) ?? 0,
            "is_paid": settlementOnly ? true : isPaid,
            "is_completed": isCompleted,
            "is_cancelled": isCancelled,
            "reminder_enabled": reminderEnabled,
            "reminder_at": reminderEnabled ? reminderDate.cloudISO8601 : NSNull(),
            "has_second_reminder": hasSecondReminder,
            "second_reminder_at": reminderEnabled && hasSecondReminder ? secondReminderDate.cloudISO8601 : NSNull(),
            "currency_code": trip?.currencyCode ?? directory.currencyCode,
            "created_at": copyAsNew ? Date.now.cloudISO8601 : (trip?.createdAt ?? Date.now.cloudISO8601),
            "updated_at": Date.now.cloudISO8601,
            "deleted_at": NSNull()
        ]
        let stopRows = stops.enumerated().compactMap { index, address -> [String: Any]? in
            let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            let existingID = copyAsNew ? nil : trip?.stops.first(where: { $0.position == index })?.id
            return ["id": existingID ?? UUID().uuidString.lowercased(), "position": index, "address": value]
        }
        let expenseRows = expenses.enumerated().compactMap { index, item -> [String: Any]? in
            guard let amount = Double(item.amount), !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let remoteID = copyAsNew ? nil : item.remoteID
            return ["id": remoteID ?? UUID().uuidString.lowercased(), "position": index,
                    "is_addition": item.isAddition, "title": item.title, "amount": amount]
        }
        if await directory.save(trip: row, stops: stopRows, expenses: expenseRows, using: auth) {
            UserDefaults.standard.set(appointmentDate.timeIntervalSince1970, forKey: "tripList.selectedDateTimestamp")
            if let tripUUID = UUID(uuidString: id) {
                await TripReminderScheduler.schedule(
                    tripID: tripUUID,
                    firstDate: reminderEnabled ? reminderDate : nil,
                    secondDate: reminderEnabled && hasSecondReminder ? secondReminderDate : nil,
                    locale: appLocale
                )
            }
            dismiss()
        }
    }
}

private struct CloudTripCustomerSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let customers: [CloudOnlineRepository.CustomerRecord]
    let initialSelection: String
    let onSelect: (CloudOnlineRepository.CustomerRecord) -> Void
    @State private var selectedID = ""
    @State private var searchText = ""

    private var matches: [CloudOnlineRepository.CustomerRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return customers.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                if matches.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "暂无客户" : "没有找到客户",
                        systemImage: "person.crop.rectangle",
                        description: Text(searchText.isEmpty ? "请先在客户管理中添加客户。" : "请尝试其他客户名称。")
                    )
                } else {
                    List(matches) { customer in
                        Button { selectedID = customer.id } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(customer.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    let contact = customer.contacts.first(where: \.isDefault) ?? customer.contacts.first
                                    Text(contact.map { "\($0.label.isEmpty ? $0.contactType : $0.label) · \($0.value)" } ?? "未填写联系方式")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selectedID == customer.id ? "checkmark.circle.fill" : "circle")
                                    .font(.title3).foregroundStyle(selectedID == customer.id ? Color.accentColor : Color.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $searchText, prompt: "搜索客户")
                }
            }
            .navigationTitle("选择客户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        guard let customer = customers.first(where: { $0.id == selectedID }) else { return }
                        onSelect(customer)
                        dismiss()
                    }.disabled(selectedID.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { selectedID = initialSelection }
    }
}

private struct CloudTripAgencySelectionView: View {
    @Environment(\.dismiss) private var dismiss
    let agencies: [CloudOnlineRepository.TravelAgencyRecord]
    let onSelect: (CloudOnlineRepository.TravelAgencyRecord) -> Void
    @State private var searchText = ""

    private var matches: [CloudOnlineRepository.TravelAgencyRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return agencies.filter {
            query.isEmpty || [$0.agencyCode, $0.name, $0.contactPerson, $0.phone]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List(matches) { agency in
                Button {
                    onSelect(agency)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(agency.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                        Text("\(agency.agencyCode) · \(agency.contactPerson.isEmpty ? "未填写联系人" : agency.contactPerson)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
            .overlay {
                if matches.isEmpty {
                    ContentUnavailableView("暂无合作旅行社", systemImage: "building.2")
                }
            }
            .searchable(text: $searchText, prompt: "搜索旅行社代码或名称")
            .navigationTitle("选择旅行社")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

@MainActor
private struct CloudTripExpenseDraft: Identifiable {
    let id = UUID()
    let remoteID: String?
    var title: String
    var amount: String
    var isAddition: Bool

    init(title: String = "", amount: String = "0", isAddition: Bool = false, remoteID: String? = nil) {
        self.title = title
        self.amount = amount
        self.isAddition = isAddition
        self.remoteID = remoteID
    }

    init(_ record: CloudOnlineRepository.TripExpenseRecord) {
        self.init(title: record.title, amount: String(record.amount), isAddition: record.isAddition, remoteID: record.id)
    }
}

private extension String {
    var cloudDate: Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: self) ?? ISO8601DateFormatter().date(from: self) ?? .now
    }

    var cloudDateText: String { cloudDate.formatted(date: .abbreviated, time: .omitted) }
    var cloudTimeText: String { cloudDate.formatted(date: .omitted, time: .shortened) }
}

private extension Date {
    var cloudISO8601: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}

private func cloudMoney(_ amount: Double, code: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    return formatter.string(from: NSNumber(value: amount)) ?? "\(code) \(amount)"
}
