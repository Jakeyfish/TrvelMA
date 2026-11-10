import SwiftUI
import SwiftData

/// Display-only preference for one trip, shared across its home and trip cards.
enum TripAmountPrivacy {
    static func defaultsKey(tripID: String) -> String { "privacy.tripAmountHidden.v2." + tripID.lowercased() }
    static let mask = "••••"
}

struct TripAmountVisibilityButton: View {
    @AppStorage private var hidden: Bool

    init(tripID: String) {
        _hidden = AppStorage(wrappedValue: false, TripAmountPrivacy.defaultsKey(tripID: tripID))
    }

    var body: some View {
        Button { hidden.toggle() } label: {
            Image(systemName: hidden ? "eye.slash" : "eye")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(hidden ? "显示金额" : "隐藏金额")
        .accessibilityHint("只切换这条行程的金额显示")
    }
}

/// Observe the preference in the Text view itself. NavigationLink/ForEach label
/// closures must not capture an old value while the eye button updates.
struct TripCardAmountText: View {
    @AppStorage private var hidden: Bool
    let value: String

    init(tripID: String, value: String) {
        self.value = value
        _hidden = AppStorage(wrappedValue: false, TripAmountPrivacy.defaultsKey(tripID: tripID))
    }

    var body: some View { Text(hidden ? TripAmountPrivacy.mask : value) }
}

// Shared by trip cards and details; only typed telephone contacts become actions.
enum TripPhoneContact {
    static func number(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ "0123456789+()- .".contains($0) }) else { return nil }
        let normalized = trimmed.filter { "0123456789+".contains($0) }
        let digits = normalized.filter { $0.isNumber }
        guard (6...20).contains(digits.count), normalized.filter({ $0 == "+" }).count <= 1,
              !normalized.contains("+") || normalized.first == "+" else { return nil }
        return normalized
    }
    static func phones(_ contacts: [(String, String)]) -> [String] {
        var seen = Set<String>()
        return contacts.compactMap { type, value in
            guard ["电话", "電話", "phone", "telephone", "tel"].contains(type.lowercased()),
                  let normalized = number(value), seen.insert(normalized).inserted else { return nil }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    @MainActor static func local(_ booking: TripBookingRecord, context: ModelContext) -> [String] {
        if let id = booking.customerUUID {
            let scope = booking.ownerScope
            let descriptor = FetchDescriptor<Custumer>(predicate: #Predicate { $0.uuid == id && $0.ownerScope == scope })
            if let customer = try? context.fetch(descriptor).first {
                return phones(customer.connecttype.filter { $0.ownerScope == scope }.map { ($0.connectlable, $0.connecttype) })
            }
        }
        return number(booking.customerContact) == nil ? [] : [booking.customerContact]
    }
    @MainActor static func cloud(_ trip: CloudOnlineRepository.CloudTripRecord, directory: CloudTripDirectoryModel) -> [String] {
        if let id = trip.customerID, let customer = directory.customers.first(where: { $0.id == id }) {
            return phones(customer.contacts.filter { $0.customerID == id }.map { ($0.label.isEmpty ? $0.contactType : $0.label, $0.value) })
        }
        return number(trip.customerContact) == nil ? [] : [trip.customerContact]
    }
}

struct TripPhoneActions: View {
    let phones: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if phones.isEmpty { Text("未填写").font(.caption).foregroundStyle(.secondary) }
            ForEach(phones, id: \.self) { phone in
                if let number = TripPhoneContact.number(phone) {
                    HStack(spacing: 14) {
                        Text(phone).font(.subheadline).textSelection(.enabled)
                        Spacer(minLength: 4)
                        Link(destination: URL(string: "sms:" + number)!) { Image(systemName: "message.fill") }
                            .accessibilityLabel("发送信息")
                        Link(destination: URL(string: "tel:" + number)!) { Image(systemName: "phone.fill") }
                            .accessibilityLabel("拨打电话")
                    }.buttonStyle(.borderless)
                }
            }
        }
    }
}
