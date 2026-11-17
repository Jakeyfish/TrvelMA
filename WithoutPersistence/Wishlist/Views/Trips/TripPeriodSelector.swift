import SwiftUI

/// Calendar boundaries match Finance: Monday weeks, local days and an exclusive end.
enum TripDateMode: String, CaseIterable, Identifiable {
    case all, day, week, month, year
    static let quickOptions: [Self] = [.day, .week, .month, .year]
    var id: Self { self }
    var title: String {
        switch self { case .all: "全部"; case .day: "天"; case .week: "周"; case .month: "本月"; case .year: "年" }
    }
    var component: Calendar.Component {
        switch self { case .all, .day: .day; case .week: .weekOfYear; case .month: .month; case .year: .year }
    }
    func interval(anchor: Date, calendar source: Calendar = .current) -> DateInterval {
        var calendar = source
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar.dateInterval(of: component, for: anchor)
            ?? DateInterval(start: calendar.startOfDay(for: anchor), duration: 0)
    }
    func includes(_ date: Date, anchor: Date, calendar: Calendar = .current) -> Bool {
        if self == .all { return true }
        let range = interval(anchor: anchor, calendar: calendar)
        return date >= range.start && date < range.end
    }
    func shifted(_ anchor: Date, by amount: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: component, value: amount, to: anchor) ?? anchor
    }
}

/// Quick filters supplement the original date strip; All stays in the existing list controls.
struct TripPeriodSelector: View {
    @Environment(\.locale) private var locale
    @Binding var period: TripDateMode
    @Binding var anchor: Date

    private var dateTitle: String {
        switch period {
        case .all, .day: return anchor.formatted(.dateTime.year().month(.wide).day().locale(locale))
        case .month: return anchor.formatted(.dateTime.year().month(.wide).locale(locale))
        case .year: return anchor.formatted(.dateTime.year().locale(locale))
        case .week:
            let range = period.interval(anchor: anchor)
            let last = Calendar.current.date(byAdding: .day, value: -1, to: range.end) ?? range.start
            return range.start.formatted(.dateTime.year().month().day().locale(locale))
                + " – " + last.formatted(.dateTime.year().month().day().locale(locale))
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(TripDateMode.quickOptions) { option in
                    Button { period = option } label: {
                        Text(LocalizedStringKey(option.title))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(period == option ? Color.accentColor : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(period == option ? Color.accentColor.opacity(0.12) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(period == option ? .isSelected : [])
                }
            }
            .padding(5)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

            HStack(spacing: 14) {
                navigationButton(-1, icon: "chevron.left", label: "上一段日期")
                Text(dateTitle).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    .accessibilityIdentifier("trip-period-range")
                navigationButton(1, icon: "chevron.right", label: "下一段日期")
            }
        }
    }

    private func navigationButton(_ amount: Int, icon: String, label: String) -> some View {
        Button {
            if period == .all { period = .day }
            anchor = period.shifted(anchor, by: amount)
        } label: {
            Image(systemName: icon).font(.system(size: 14, weight: .bold))
                .frame(width: 38, height: 38)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(LocalizedStringKey(label))
    }
}
