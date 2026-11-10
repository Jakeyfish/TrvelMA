/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A travel trip with a name, activities, and associated photo.
*/

import Foundation

/// A travel trip with a name, activities, and associated photo.
@Observable
class Trip: Identifiable {

    /// The name of the trip.
    var name: String
    
    /// The collection this trip belongs to.
    var collection: TripCollection
    
    /// The URL of the photo associated with the trip.
    var photoURL: URL

    /// The activities associated with the trip.
    ///
    /// The dictionary allows for efficient lookup of activities by their IDs,
    /// without iterating through the collection.
    var activities: [Activity.ID: Activity]

    /// The date and time when the trip was created.
    let creationDate = Date.now

    /// The subtitle for the trip that provides additional descriptive text.
    var subtitle: String?

    /// Creates a new trip with the specified details.
    ///
    /// - Parameters:
    ///   - name: The name of the trip.
    ///   - collection: The collection this trip belongs to.
    ///   - photoURL: The URL of the photo associated with the trip.
    ///   - activities: Optional; The activities associated with this trip.
    ///     Defaults to an empty collection.
    ///   - subtitle: Optional; The subtitle for the trip that provides additional descriptive text.
    init(
        name: String,
        collection: TripCollection,
        photoURL: URL,
        activities: [Activity] = [],
        subtitle: String? = nil
    ) {
        self.name = name
        self.collection = collection
        self.photoURL = photoURL
        self.activities = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })
        self.subtitle = subtitle
    }
}

/// Validates settlement values before either persistence path changes a trip.
enum SettlementValidation {
    struct Expense {
        let title: String
        let amount: Double?
        let isAddition: Bool
    }

    enum Failure: Equatable, LocalizedError {
        case invalidFare
        case negativeFare
        case invalidExpense
        case invalidTotal

        var errorDescription: String? { message }

        var message: String {
            switch self {
            case .invalidFare: "请输入有效的行程费用和小费。"
            case .negativeFare: "行程费用和小费不能小于 0。"
            case .invalidExpense: "请为每条费用明细填写项目名称和大于 0 的有效金额。"
            case .invalidTotal: "结算金额超出可计算范围，请检查费用和小费。"
            }
        }
    }

    static func validate(fare: Double?, tip: Double?, expenses: [Expense]) -> Failure? {
        guard let fare, let tip, fare.isFinite, tip.isFinite else { return .invalidFare }
        guard fare >= 0, tip >= 0 else { return .negativeFare }
        var total = fare + tip
        guard total.isFinite else { return .invalidTotal }
        for expense in expenses {
            let title = expense.title.trimmingCharacters(in: .whitespacesAndNewlines)
            // Only an unnamed, explicitly zero row is an unused draft.
            if title.isEmpty, expense.amount == 0 { continue }
            guard !title.isEmpty, let amount = expense.amount, amount.isFinite, amount > 0 else {
                return .invalidExpense
            }
            total += expense.isAddition ? amount : -amount
            guard total.isFinite else { return .invalidTotal }
        }
        return nil
    }

    /// Restores only financial fields if persistence fails; unrelated pending edits survive.
    @MainActor
    static func save(
        booking: TripBookingRecord,
        fare: Double,
        tip: Double,
        expenses: [TripExpenseAdjustment],
        markPaid: Bool = true,
        persist: () throws -> Void
    ) throws {
        if let failure = validate(fare: fare, tip: tip, expenses: expenses.map {
            Expense(title: $0.title, amount: $0.amount, isAddition: $0.isAddition)
        }) { throw failure }

        let originalFare = booking.price
        let originalTip = booking.tip
        let originalExpenses = booking.expenseAdjustmentsJSON
        let originalPaid = booking.isPaid
        let originalUpdatedAt = booking.updatedAt
        booking.price = fare
        booking.tip = tip
        booking.expenseAdjustments = expenses.filter {
            !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.amount != 0
        }
        if markPaid { booking.isPaid = true }
        booking.updatedAt = .now
        do {
            try persist()
        } catch {
            booking.price = originalFare
            booking.tip = originalTip
            booking.expenseAdjustmentsJSON = originalExpenses
            booking.isPaid = originalPaid
            booking.updatedAt = originalUpdatedAt
            throw error
        }
    }

    static func expenseAmount(from text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? 0 : Double(value)
    }
}

/// A total display order shared by local and online trip lists.
/// Ignore the hidden date carried by a time picker and subsecond precision lost in sync.
struct TripScheduleSortKey {
    private let day: Date
    private let clockSecond: Int
    private let creationSecond: TimeInterval
    private let recordID: String

    init(appointmentDate: Date, appointmentTime: Date, createdAt: Date, id: String, calendar: Calendar = .current) {
        day = calendar.startOfDay(for: appointmentDate)
        let time = calendar.dateComponents([.hour, .minute, .second], from: appointmentTime)
        clockSecond = (time.hour ?? 0) * 3600 + (time.minute ?? 0) * 60 + (time.second ?? 0)
        creationSecond = createdAt.timeIntervalSince1970.rounded(.down)
        recordID = id.lowercased()
    }

    init(appointmentDate: String, appointmentTime: String, createdAt: String, id: String, calendar: Calendar = .current) {
        self.init(appointmentDate: Self.parse(appointmentDate), appointmentTime: Self.parse(appointmentTime),
                  createdAt: Self.parse(createdAt), id: id, calendar: calendar)
    }

    func precedes(_ other: Self) -> Bool {
        if day != other.day { return day < other.day }
        if clockSecond != other.clockSecond { return clockSecond < other.clockSecond }
        if creationSecond != other.creationSecond { return creationSecond < other.creationSecond }
        return recordID < other.recordID
    }

    static func sorted<Record>(_ records: [Record], key: (Record) -> Self) -> [Record] {
        records.map { (record: $0, key: key($0)) }
            .sorted { $0.key.precedes($1.key) }
            .map(\.record)
    }

    private static func parse(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value) ?? .distantPast
    }
}

/// Apply an execution-state change only if persistence succeeds. Financial and
/// unrelated pending edits are deliberately left alone on failure.
enum TripExecutionState {
    @MainActor
    static func save(booking: TripBookingRecord, completed: Bool, cancelled: Bool,
                     cancelReminders: (UUID) -> Void = TripReminderScheduler.cancel,
                     persist: () throws -> Void) throws {
        let previousCompleted = booking.isCompleted
        let previousCancelled = booking.isCancelled
        let previousUpdatedAt = booking.updatedAt
        booking.isCompleted = completed
        booking.isCancelled = cancelled
        booking.updatedAt = .now
        do {
            try persist()
        } catch {
            booking.isCompleted = previousCompleted
            booking.isCancelled = previousCancelled
            booking.updatedAt = previousUpdatedAt
            throw error
        }
        if completed || cancelled { cancelReminders(booking.id) }
    }
}

/// Commit a selected flight before presenting it as saved. Restore only the
/// flight fields on failure, leaving unrelated pending changes intact.
enum FlightSelectionPersistence {
    @MainActor
    static func save(booking: TripBookingRecord, snapshot: SavedFlightSelection,
                     persist: () throws -> Void) throws {
        let encoded = try JSONEncoder().encode(snapshot)
        let previousJSON = booking.flightSelectionSnapshotJSON
        let previousDeparture = booking.flightDepartureTime
        let previousArrival = booking.flightEstimatedArrivalTime
        let previousTerminal = booking.flightArrivalTerminal
        let previousBaggage = booking.flightBaggageCarousel
        let previousUpdatedAt = booking.updatedAt
        booking.flightSelectionSnapshotJSON = String(decoding: encoded, as: UTF8.self)
        booking.flightDepartureTime = snapshot.selected.departureTime
        booking.flightEstimatedArrivalTime = snapshot.selected.estimatedArrivalTime
        booking.flightArrivalTerminal = snapshot.selected.arrivalTerminal
        booking.flightBaggageCarousel = snapshot.selected.baggageCarousel
        booking.updatedAt = .now
        do {
            try persist()
        } catch {
            booking.flightSelectionSnapshotJSON = previousJSON
            booking.flightDepartureTime = previousDeparture
            booking.flightEstimatedArrivalTime = previousArrival
            booking.flightArrivalTerminal = previousTerminal
            booking.flightBaggageCarousel = previousBaggage
            booking.updatedAt = previousUpdatedAt
            throw error
        }
    }
}

/// Shared by local and cloud finance totals, counts and snapshot lists.
enum FinancialTripInclusion {
    static func includes(cancelled: Bool, date: Date?, in interval: DateInterval) -> Bool {
        guard !cancelled, let date else { return false }
        return date >= interval.start && date < interval.end
    }
}
