//
//  NewTripFormModel.swift
//  Wishlist
//
//  Created by Tony.W on 6/14/26.
//  Copyright © 2026 Apple. All rights reserved.
//


import SwiftUI
import SwiftData
import MapKit
import Combine
import CoreLocation
import UserNotifications

enum SmartPickupReminderPlan {
    /// Notification triggers and the editor use minute precision. Never invent
    /// two identical reminders or put an expired reminder into the saved draft.
    static func dates(before appointment: Date, now: Date = .now, calendar: Calendar = .current) -> [Date] {
        func minute(_ date: Date) -> Date {
            calendar.dateInterval(of: .minute, for: date)?.start ?? date
        }
        let preferred = [calendar.date(byAdding: .day, value: -1, to: appointment)] +
            [120, 60, 30, 15, 5, 1].map { calendar.date(byAdding: .minute, value: -$0, to: appointment) }
        var dates: [Date] = []
        for candidate in preferred.compactMap({ $0 }).map(minute) where candidate > now && candidate < appointment {
            if !dates.contains(candidate) { dates.append(candidate) }
            if dates.count == 2 { return dates.sorted() }
        }
        for candidate in [minute(now).addingTimeInterval(60), minute(appointment).addingTimeInterval(-60)] where candidate > now && candidate < appointment {
            if !dates.contains(candidate) { dates.append(candidate) }
        }
        return dates.count >= 2 ? Array(dates.sorted().prefix(2)) : []
    }
}

enum PickupAgencyMatcher {
    /// Known names only: similar-looking unrelated agencies must not be selected.
    static func matches(_ name: String) -> Bool {
        let folded = name.folding(options: [.widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().replacingOccurrences(of: "風", with: "风").replacingOccurrences(of: "遊", with: "游")
        let key = String(String.UnicodeScalarView(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
        return ["途风", "途风旅行", "途风旅游", "途风旅行社", "tours4fun", "途风tours4fun", "tours4fun途风",
                "途风旅游tours4fun", "tours4fun途风旅游", "途风旅行社tours4fun", "tours4fun途风旅行社", "途风旅行tours4fun", "tours4fun途风旅行"].contains(key)
    }
}

/// Structured Tours4Fun pickup import. Parsing is local and never sends pasted text to a service.
struct RecognizedPickupOrder: Identifiable {
    let id = UUID()
    var orderNumber: String
    var date: Date?
    var inferredYear: Bool
    var flight: String
    var airport: String
    var estimatedArrival: String?
    var contact: String?
    var phone: String?
    var passengers: String?
    var luggage: String?
    var hotel: String?
    var address: String?
    var rawText: String

    var destination: String? {
        guard let address, !address.isEmpty else { return nil }
        return [hotel, address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
    var dateText: String {
        guard let date else { return "日期无效，请修改原文后重试" }
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    var pickupDateTime: Date? {
        guard let date, let estimatedArrival else { return nil }
        let parts = estimatedArrival.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = parts[0]; components.minute = parts[1]
        guard let value = calendar.date(from: components),
              calendar.component(.hour, from: value) == parts[0],
              calendar.component(.minute, from: value) == parts[1] else { return nil }
        return value
    }
    func reminderDates(now: Date = .now) -> [Date] {
        guard let pickupDateTime else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return SmartPickupReminderPlan.dates(before: pickupDateTime, now: now, calendar: calendar)
    }
    func apply(to form: inout NewTripFormModel, agencyCode: String? = nil, now: Date = .now) {
        guard let date, let pickupDateTime else { return }
        let sameAgency = PickupAgencyMatcher.matches(form.travelAgencyName)
        form.travelAgencyCode = agencyCode ?? (sameAgency ? form.travelAgencyCode : "")
        form.orderSource = "旅行社订单"
        form.travelAgencyName = "途风"
        form.travelAgencyOrderNumber = orderNumber
        form.serviceType = "接机"
        form.appointmentDate = date
        form.appointmentTime = pickupDateTime
        let reminders = reminderDates(now: now)
        form.reminderEnabled = reminders.count == 2
        form.hasSecondReminder = reminders.count == 2
        if reminders.count == 2 { form.reminderDateTime = reminders[0]; form.secondReminderDateTime = reminders[1] }
        form.reminderDateWasCustomized = false
        form.secondReminderDateWasCustomized = false
        form.copiedReminderDefaultsToTwoHours = false
        form.flightdate = date
        form.flightInfo = flight
        form.locationStart = airport
        if let destination { form.locationEnd = destination }
        if let contact { form.customerName = contact; form.selectedCustomerUUID = nil }
        if let phone { form.custemerConnect = phone }
        if let passengers { form.customerCount = passengers }
        if let luggage { form.customerStuff = luggage }
        form.flightSelectionSnapshotJSON = ""
        form.flightDepartureTime = ""
        form.flightEstimatedArrivalTime = estimatedArrival ?? ""
        form.flightArrivalTerminal = ""
        form.flightBaggageCarousel = ""
        let arrival = estimatedArrival.map { "\n航班预计抵达：\($0)（洛杉矶当地时间；已用作接客时间）" } ?? ""
        let note = "途风订单号：\(orderNumber)\(arrival)\n原始订单：\n\(rawText)"
        if !form.TripMemo.contains(note) {
            form.TripMemo += (form.TripMemo.isEmpty ? "" : "\n\n") + note
        }
    }
}

enum PickupOrderRecognizer {
    static func recognize(_ raw: String, now: Date = .now) -> RecognizedPickupOrder? {
        let text = raw.replacingOccurrences(of: "\u{00a0}", with: " ").replacingOccurrences(of: "\r\n", with: "\n")
        func groups(_ pattern: String, in value: String? = nil) -> [String]? {
            let value = value ?? text
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .anchorsMatchLines]),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
            return (1..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: value).map { String(value[$0]).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            }
        }
        func field(_ label: String) -> String? {
            guard let value = groups("(?:" + label + ")[^\\S\\r\\n]*[：:][^\\S\\r\\n]*([^\\r\\n]+)")?.first,
                  !value.isEmpty else { return nil }
            return value
        }
        guard let number = groups(#"(?:订单号|訂單號)\s*[：:]\s*(C-\d+-US)\b"#)?.first,
              let dateLine = field("接机日期|接機日期"),
              let flight = groups(#"(?:航班号|航班號)\s*[：:]\s*([A-Z0-9]{2}\s*\d{1,4})\b"#)?.first,
              let airport = groups(#"(?:抵达机场|抵達機場)\s*[：:]\s*([A-Z]{3})\b"#)?.first,
              airport.uppercased() == "LAX",
              let guestAddress = field("客人地址"),
              let contactLine = field("联络人|聯絡人|联系人|聯繫人"),
              field("类型|類型").map({ $0.hasPrefix("接机") || $0.hasPrefix("接機") }) ?? true else { return nil }
        let trailingYear = groups(#"^(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})(?=$|[\s，,;；])"#, in: dateLine)
        let components = trailingYear.map { [$0[2], $0[0], $0[1]] } ??
            groups(#"^(?:(\d{4})[年/.-])?(\d{1,2})[月/.-](\d{1,2})(?:日)?(?=$|[\s，,;；])"#, in: dateLine)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var date: Date?
        let explicitYear = components.flatMap { Int($0[0]) }
        if let components, let month = Int(components[1]), let day = Int(components[2]) {
            let today = calendar.dateComponents([.year, .month, .day], from: now)
            let past = month < today.month! || (month == today.month! && day < today.day!)
            let year = explicitYear ?? (today.year! + (past ? 1 : 0))
            if let candidate = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
               calendar.component(.year, from: candidate) == year,
               calendar.component(.month, from: candidate) == month,
               calendar.component(.day, from: candidate) == day { date = candidate }
        }
        let time = groups(#"(?:接机时间|接機時間|抵达时间|抵達時間)[^\S\r\n]*[：:][^\S\r\n]*[^\d\r\n]{0,12}(\d{1,2})[:：](\d{2})(?!\d)"#)
        var arrival: String?
        if let time, let hour = Int(time[0]), let minute = Int(time[1]), (0...23).contains(hour), (0...59).contains(minute) {
            arrival = String(format: "%02d:%02d", hour, minute)
        }
        let contact = contactLine.components(separatedBy: CharacterSet(charactersIn: "（(")).first?.trimmingCharacters(in: .whitespaces)
        let phoneText = groups(#"(?:联络电话|聯絡電話|联系电话|聯繫電話)[^\S\r\n]*[：:][^\S\r\n]*(\+?\d[\d ()（）-]*)"#)?.first
        let phone = phoneText.map { value -> String in
            let digits = value.filter { $0.isASCII && $0.isNumber }
            return (value.hasPrefix("+") || digits.hasPrefix("886") ? "+" : "") + digits
        }
        let addressParts = groups(#"^(.*?)\s*(?:住址|地址)\s*[：:]\s*(.+)$"#, in: guestAddress)
        let hotel = addressParts?.first
        let address = addressParts?[1] ?? guestAddress
        return RecognizedPickupOrder(orderNumber: number.uppercased(), date: date, inferredYear: explicitYear == nil,
            flight: flight.replacingOccurrences(of: " ", with: "").uppercased(), airport: airport.uppercased(), estimatedArrival: arrival,
            contact: contact, phone: phone, passengers: groups(#"(?:人数|人數)\s*[：:]\s*(\d+)\s*人"#)?.first ?? groups(#"[（(]\s*(\d+)\s*人\s*[）)]"#, in: contactLine)?.first,
            luggage: groups(#"(\d+)\s*件\s*行李"#)?.first, hotel: hotel, address: address, rawText: raw)
    }
}

/// Shared by local and cloud trip editors; applying only changes their unsaved draft.
struct SmartTripInput: View {
    @Binding var text: String
    let apply: (RecognizedPickupOrder) -> Void
    @State private var recognized: RecognizedPickupOrder?
    @State private var error: String?
    @State private var notificationNotice: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LimitedIMETextEditor(text: $text, maxLength: 5000, fontSize: 14)
                .frame(height: 110)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.2)))
            Text("智能识别录入")
                .font(.caption).foregroundStyle(.secondary)
            Button("识别订单") {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                if let result = PickupOrderRecognizer.recognize(text) { recognized = result; error = nil }
                else { error = "未识别为途风 LAX 接机格式，请检查订单号、接机日期、航班、机场、客人地址和联系人标签。" }
            }.buttonStyle(.borderedProminent).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            if let notificationNotice { Text(notificationNotice).font(.caption).foregroundStyle(.orange) }
        }
        .sheet(item: $recognized) { result in
            NavigationStack {
                List {
                    Section("识别结果") {
                        LabeledContent("订单来源", value: "旅行社 · 途风")
                        LabeledContent("订单号", value: result.orderNumber)
                        LabeledContent("接机日期", value: result.dateText)
                        LabeledContent("航班", value: result.flight)
                        LabeledContent("起点机场", value: result.airport)
                        LabeledContent("接客时间（预计抵达）", value: result.estimatedArrival ?? "未识别")
                        LabeledContent("联系人", value: result.contact ?? "未识别")
                        LabeledContent("电话", value: result.phone ?? "未识别")
                        LabeledContent("人数 / 行李", value: "\(result.passengers ?? "待填") 人 / \(result.luggage ?? "待填") 件")
                        LabeledContent("目的地酒店", value: result.hotel ?? "未识别")
                        LabeledContent("目的地地址", value: result.address ?? "未识别")
                    }
                    Section("请确认") {
                        if result.inferredYear { Text("未写年份时，按洛杉矶当地今天比较：同日或未来取本年，已过日期取明年。") }
                        Text("接客时间取航班预计抵达。自动预设前一天、提前2小时两条提醒；临近时调整为仍未过去的时间。报价请确认，航站楼需查航班后选择。")
                        if result.reminderDates().count != 2 { Text("接客时间已过或太近，无法安排两条未来提醒，请手动调整。").foregroundStyle(.orange) }
                        Text("填入会替换已识别字段；报价及未识别字段保留。订单号填入独立的旅行社订单号字段，原文也留在备注。")
                        if result.pickupDateTime == nil { Text("日期或抵达时间无效，请返回修改原文。不会自动改成其他日期。").foregroundStyle(.orange) }
                    }
                }
                .navigationTitle("识别预览")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("返回") { recognized = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("填入行程") {
                            apply(result); recognized = nil
                            if result.reminderDates().count == 2 {
                                Task {
                                    let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                                    notificationNotice = granted ? nil : "两条提醒已预设，但系统未允许通知；请在系统设置中允许通知后保存。"
                                }
                            }
                        }.disabled(result.pickupDateTime == nil)
                    }
                }
            }
        }
    }
}

// MARK: - 1. 本地安全行程数据模型
struct NewTripFormModel {
    var id: UUID = .init()
    var serviceType: String = "接机"
    var quickInputText: String = ""
    var orderSource: String = "普通客户"
    var travelAgencyCode: String = ""
    var travelAgencyName: String = ""
    var travelAgencyOrderNumber: String = ""
    var customerSelection: String = "客户选择"
    var selectedCustomerUUID: String?
    var customerName: String = ""
    var custemerConnect: String = ""
    var customerCount: String = "1"
    var customerStuff: String = "0"
    var appointmentDate: Date = Date()
    var appointmentTime: Date = Date()
    var locationStart: String = ""
    var locationStops: [String] = []
    var locationEnd: String = ""
    var flightInfo: String = ""
    var flightdate: Date = Date()
    var flightDepartureTime: String = ""
    var flightEstimatedArrivalTime: String = ""
    var flightArrivalTerminal: String = ""
    var flightBaggageCarousel: String = ""
    var flightSelectionSnapshotJSON: String = ""
    var TripMemo: String = ""
    var TripPrice: Double = 0.00
    var isPaid: Bool = false
    var reminderEnabled = false
    var reminderDateTime = Date.now
    var hasSecondReminder = false
    var secondReminderDateTime = Date.now
    var reminderDateWasCustomized = false
    var secondReminderDateWasCustomized = false
    var copiedReminderDefaultsToTwoHours = false

    init(booking: TripBookingRecord? = nil, copying: Bool = false) {
        guard let booking else { return }
        id = copying ? UUID() : booking.id
        serviceType = booking.serviceType
        orderSource = booking.orderSource
        travelAgencyCode = booking.travelAgencyCode
        travelAgencyName = booking.travelAgencyName
        travelAgencyOrderNumber = booking.travelAgencyOrderNumber
        customerName = booking.customerName
        selectedCustomerUUID = booking.customerUUID
        custemerConnect = booking.customerContact
        customerCount = booking.customerCount
        customerStuff = booking.customerStuff
        appointmentDate = copying ? .now : booking.appointmentDate
        appointmentTime = booking.appointmentTime
        locationStart = booking.locationStart
        locationStops = booking.locationStops
        locationEnd = booking.locationEnd
        flightInfo = booking.flightInfo
        flightdate = copying ? .now : booking.flightDate
        flightDepartureTime = booking.flightDepartureTime ?? ""
        flightEstimatedArrivalTime = booking.flightEstimatedArrivalTime ?? ""
        flightArrivalTerminal = booking.flightArrivalTerminal ?? ""
        flightBaggageCarousel = booking.flightBaggageCarousel ?? ""
        flightSelectionSnapshotJSON = copying ? "" : booking.flightSelectionSnapshotJSON
        TripMemo = booking.memo
        TripPrice = booking.price
        isPaid = copying ? false : booking.isPaid
        reminderEnabled = copying ? true : booking.reminderEnabled
        reminderDateTime = booking.reminderDateTime ?? .now
        hasSecondReminder = copying ? false : booking.hasSecondReminder
        secondReminderDateTime = booking.secondReminderDateTime ?? .now
        reminderDateWasCustomized = copying ? false : booking.reminderDateTime != nil
        secondReminderDateWasCustomized = copying ? false : booking.secondReminderDateTime != nil
        copiedReminderDefaultsToTwoHours = copying
    }

    mutating func updateDefaultReminderDateTimes() {
        var appointmentComponents = Calendar.current.dateComponents([.year, .month, .day], from: appointmentDate)
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: appointmentTime)
        appointmentComponents.hour = timeComponents.hour
        appointmentComponents.minute = timeComponents.minute
        let appointment = Calendar.current.date(from: appointmentComponents) ?? appointmentDate

        let dates = SmartPickupReminderPlan.dates(before: appointment)
        guard dates.count == 2 else {
            reminderEnabled = false
            hasSecondReminder = false
            return
        }
        if !reminderDateWasCustomized {
            reminderDateTime = copiedReminderDefaultsToTwoHours && !hasSecondReminder ? dates[1] : dates[0]
        }
        if !secondReminderDateWasCustomized { secondReminderDateTime = dates[1] }
    }

    mutating func adjustRemindersForAppointmentChange() {
        var appointmentComponents = Calendar.current.dateComponents([.year, .month, .day], from: appointmentDate)
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: appointmentTime)
        appointmentComponents.hour = timeComponents.hour
        appointmentComponents.minute = timeComponents.minute
        let appointment = Calendar.current.date(from: appointmentComponents) ?? appointmentDate

        let dates = SmartPickupReminderPlan.dates(before: appointment)
        if dates.count == 2 {
            reminderDateTime = dates[0]
            secondReminderDateTime = dates[1]
        } else {
            reminderEnabled = false
            hasSecondReminder = false
        }
        reminderDateWasCustomized = false
        secondReminderDateWasCustomized = false
        copiedReminderDefaultsToTwoHours = false
    }

}

@Model
final class TripBookingRecord {
    @Attribute(.unique) var id: UUID
    var ownerScope: String = "local"
    var serviceType: String
    var orderSource: String
    var travelAgencyCode: String = ""
    var travelAgencyName: String = ""
    var travelAgencyOrderNumber: String = ""
    var customerName: String
    var customerUUID: String? = nil
    var customerContact: String
    var customerCount: String
    var customerStuff: String
    var appointmentDate: Date
    var appointmentTime: Date
    var locationStart: String
    var locationStop: String = ""
    var additionalStopsJSON: String = "[]"
    var locationEnd: String
    var flightInfo: String
    var flightDate: Date
    var flightDepartureTime: String?
    var flightEstimatedArrivalTime: String?
    var flightArrivalTerminal: String?
    var flightBaggageCarousel: String?
    var flightSelectionSnapshotJSON: String = ""
    var memo: String
    var price: Double
    var tip: Double = 0
    var expenseAdjustmentsJSON: String = "[]"
    var isPaid: Bool
    var isCompleted: Bool
    var isCancelled: Bool = false
    var reminderEnabled: Bool = false
    var reminderDateTime: Date?
    var hasSecondReminder: Bool = false
    var secondReminderDateTime: Date?
    var createdAt: Date
    // Optional so existing SwiftData stores can migrate without requiring a
    // synthetic timestamp. Sync comparisons fall back to createdAt for legacy rows.
    var updatedAt: Date? = nil
    /// Cloud timestamp last confirmed by a successful download or upload.
    var syncBaseUpdatedAt: Date? = nil

    var locationStops: [String] {
        get {
            let extraStops = (try? JSONDecoder().decode([String].self, from: Data(additionalStopsJSON.utf8))) ?? []
            let stops = [locationStop] + extraStops
            return stops.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ? [] : stops
        }
        set {
            let stops = newValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            locationStop = stops.first ?? ""
            let extraStops = Array(stops.dropFirst())
            if let data = try? JSONEncoder().encode(extraStops), let json = String(data: data, encoding: .utf8) {
                additionalStopsJSON = json
            } else {
                additionalStopsJSON = "[]"
            }
        }
    }

    var expenseAdjustments: [TripExpenseAdjustment] {
        get {
            guard let data = expenseAdjustmentsJSON.data(using: .utf8),
                  let items = try? JSONDecoder().decode([TripExpenseAdjustment].self, from: data) else { return [] }
            return items
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                expenseAdjustmentsJSON = "[]"
                return
            }
            expenseAdjustmentsJSON = json
        }
    }

    init(form: NewTripFormModel) {
        id = form.id
        ownerScope = DataOwnership.activeScope
        serviceType = form.serviceType
        orderSource = form.orderSource
        travelAgencyCode = form.orderSource == "旅行社订单" ? form.travelAgencyCode : ""
        travelAgencyName = form.orderSource == "旅行社订单" ? form.travelAgencyName : ""
        travelAgencyOrderNumber = form.orderSource == "旅行社订单" ? form.travelAgencyOrderNumber.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        customerName = form.customerName
        customerUUID = form.selectedCustomerUUID
        customerContact = form.custemerConnect
        customerCount = form.customerCount
        customerStuff = form.customerStuff
        appointmentDate = form.appointmentDate
        appointmentTime = form.appointmentTime
        locationStart = form.locationStart
        let stops = form.locationStops.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        locationStop = stops.first ?? ""
        let extraStops = Array(stops.dropFirst())
        if let data = try? JSONEncoder().encode(extraStops), let json = String(data: data, encoding: .utf8) {
            additionalStopsJSON = json
        }
        locationEnd = form.locationEnd
        flightInfo = form.flightInfo
        flightDate = form.flightdate
        flightDepartureTime = form.flightDepartureTime.isEmpty ? nil : form.flightDepartureTime
        flightEstimatedArrivalTime = form.flightEstimatedArrivalTime.isEmpty ? nil : form.flightEstimatedArrivalTime
        flightArrivalTerminal = form.flightArrivalTerminal.isEmpty ? nil : form.flightArrivalTerminal
        flightBaggageCarousel = form.flightBaggageCarousel.isEmpty ? nil : form.flightBaggageCarousel
        flightSelectionSnapshotJSON = form.flightSelectionSnapshotJSON
        memo = form.TripMemo
        price = form.TripPrice
        isPaid = form.isPaid
        isCompleted = false
        isCancelled = false
        reminderEnabled = form.reminderEnabled
        reminderDateTime = form.reminderEnabled ? form.reminderDateTime : nil
        hasSecondReminder = form.reminderEnabled && form.hasSecondReminder
        secondReminderDateTime = form.reminderEnabled && form.hasSecondReminder ? form.secondReminderDateTime : nil
        createdAt = .now
        updatedAt = .now
        syncBaseUpdatedAt = nil
    }

    init(copying source: TripBookingRecord) {
        id = source.id
        ownerScope = source.ownerScope
        serviceType = source.serviceType
        orderSource = source.orderSource
        travelAgencyCode = source.travelAgencyCode
        travelAgencyName = source.travelAgencyName
        travelAgencyOrderNumber = source.travelAgencyOrderNumber
        customerName = source.customerName
        customerUUID = source.customerUUID
        customerContact = source.customerContact
        customerCount = source.customerCount
        customerStuff = source.customerStuff
        appointmentDate = source.appointmentDate
        appointmentTime = source.appointmentTime
        locationStart = source.locationStart
        locationStop = source.locationStop
        additionalStopsJSON = source.additionalStopsJSON
        locationEnd = source.locationEnd
        flightInfo = source.flightInfo
        flightDate = source.flightDate
        flightDepartureTime = source.flightDepartureTime
        flightEstimatedArrivalTime = source.flightEstimatedArrivalTime
        flightArrivalTerminal = source.flightArrivalTerminal
        flightBaggageCarousel = source.flightBaggageCarousel
        flightSelectionSnapshotJSON = source.flightSelectionSnapshotJSON
        memo = source.memo
        price = source.price
        tip = source.tip
        expenseAdjustmentsJSON = source.expenseAdjustmentsJSON
        isPaid = source.isPaid
        isCompleted = source.isCompleted
        isCancelled = source.isCancelled
        reminderEnabled = source.reminderEnabled
        reminderDateTime = source.reminderDateTime
        hasSecondReminder = source.hasSecondReminder
        secondReminderDateTime = source.secondReminderDateTime
        createdAt = source.createdAt
        updatedAt = source.updatedAt
        syncBaseUpdatedAt = source.syncBaseUpdatedAt
    }

    func update(from form: NewTripFormModel) {
        updatedAt = .now
        serviceType = form.serviceType
        orderSource = form.orderSource
        travelAgencyCode = form.orderSource == "旅行社订单" ? form.travelAgencyCode : ""
        travelAgencyName = form.orderSource == "旅行社订单" ? form.travelAgencyName : ""
        travelAgencyOrderNumber = form.orderSource == "旅行社订单" ? form.travelAgencyOrderNumber.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        customerName = form.customerName
        customerUUID = form.selectedCustomerUUID
        customerContact = form.custemerConnect
        customerCount = form.customerCount
        customerStuff = form.customerStuff
        appointmentDate = form.appointmentDate
        appointmentTime = form.appointmentTime
        locationStart = form.locationStart
        locationStops = form.locationStops
        locationEnd = form.locationEnd
        flightInfo = form.flightInfo
        flightDate = form.flightdate
        flightDepartureTime = form.flightDepartureTime.isEmpty ? nil : form.flightDepartureTime
        flightEstimatedArrivalTime = form.flightEstimatedArrivalTime.isEmpty ? nil : form.flightEstimatedArrivalTime
        flightArrivalTerminal = form.flightArrivalTerminal.isEmpty ? nil : form.flightArrivalTerminal
        flightBaggageCarousel = form.flightBaggageCarousel.isEmpty ? nil : form.flightBaggageCarousel
        flightSelectionSnapshotJSON = form.flightSelectionSnapshotJSON
        memo = form.TripMemo
        price = form.TripPrice
        isPaid = form.isPaid
        reminderEnabled = form.reminderEnabled
        reminderDateTime = form.reminderEnabled ? form.reminderDateTime : nil
        let shouldScheduleSecondReminder = form.reminderEnabled && form.hasSecondReminder
        hasSecondReminder = shouldScheduleSecondReminder
        secondReminderDateTime = shouldScheduleSecondReminder ? form.secondReminderDateTime : nil
    }
}

struct TripExpenseAdjustment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var isAddition = false
    var title = ""
    var amount: Double = 0
}

// MARK: - 2. 主页面视图（支持 Canvas 完美双向独立预览）
struct AddTripFormView: View {
    @Environment(\.dismiss) private var dismiss // 用于关闭页面
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var appLocale
    @State private var formData: NewTripFormModel
    @Binding var isPresented: Bool
    @State private var errorMessage: String?
    // 实例化地址联想核心状态机
    @StateObject private var searcher = AddressAutocompleteSearcher()

    private let booking: TripBookingRecord?
    private let isCopying: Bool

    init(isPresented: Binding<Bool>, booking: TripBookingRecord? = nil, copying: Bool = false) {
        self._isPresented = isPresented
        self.booking = booking
        self.isCopying = copying
        self._formData = State(initialValue: NewTripFormModel(booking: booking, copying: copying))
    }


    var body: some View {
        NavigationStack {
            ZStack {
                AddressSuggestionScrollView {
                    VStack(spacing: 14) {
                        // ===== 模块 1：服务类型网格 =====
                        ServiceTypeSection(formData: $formData)
                        
                        // ===== 模块 2：快速智能录入 =====
                        QuickInputSection(formData: $formData)
                        
                        // ===== 模块 3：订单来源选择 =====
                        OrderSourceSection(formData: $formData)

                        if formData.orderSource == "旅行社订单" {
                            TravelAgencyTripSection(formData: $formData)
                        }
                        
                        // ===== 模块 4：客户选择输入 =====
                        CustomerSelectionSection(formData: $formData)
    
                        // ===== 模块 5：行程详细信息输入 =====

                        TripDeteilSection(formData: $formData,searcher: searcher)
                        // ===== 模块 6：行程金额和备注信息输入 =====
                        
                        TripDeteilSectionMoney(formData: $formData)

                        // ===== 模块 7：行程和结算状态 =====
                        TripStatusSection(formData: $formData)

                        // ===== 模块 8：系统提醒 =====
                        TripReminderSection(formData: $formData)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
                // Address autocomplete inserts results while the user is typing.
                // Keep that layout update from being treated as an interactive scroll
                // gesture that dismisses the keyboard after the first character.
                .scrollDismissesKeyboard(.never)
                .background(Color.primary.opacity(0.015))
                .onAppear { formData.updateDefaultReminderDateTimes() }
                .onChange(of: formData.appointmentDate) { _, _ in formData.adjustRemindersForAppointmentChange() }
                .onChange(of: formData.appointmentTime) { _, _ in formData.adjustRemindersForAppointmentChange() }
                .navigationTitle(isCopying || booking == nil ? "新增行程" : "编辑行程")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            dismiss()
                            isPresented = false
                        }
                        .foregroundStyle(.secondary)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            saveTrip()
                        }
                        .tint(.accentColor)
                        .font(.headline)
                    }
                }
                // 确保导航组件在 Canvas 中一并被强制渲染为高档暗黑色系
//                .toolbarBackground(Color(red: 0.09, green: 0.10, blue: 0.12), for: .navigationBar)
//                .toolbarBackground(.visible, for: .navigationBar)
//                .toolbarColorScheme(.dark, for: .navigationBar)
                .alert("无法保存行程", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                    Button("确定", role: .cancel) { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
            }
        }
        .presentationDetents([.large])
    }

    private func saveTrip() {
        let name = formData.customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "请输入客户姓名后再保存行程。"
            return
        }
        if formData.reminderEnabled {
            let reminderDates = formData.hasSecondReminder
                ? [formData.reminderDateTime, formData.secondReminderDateTime]
                : [formData.reminderDateTime]
            guard reminderDates.allSatisfy({ $0 > .now }) else {
                errorMessage = "提醒时间必须晚于当前时间。"
                return
            }
        }
        formData.customerName = name
        let record: TripBookingRecord
        if let booking, !isCopying {
            record = booking
            record.update(from: formData)
        } else {
            record = TripBookingRecord(form: formData)
            modelContext.insert(record)
        }
        do {
            try modelContext.save()
            UserDefaults.standard.set(formData.appointmentDate.timeIntervalSince1970, forKey: "tripList.selectedDateTimestamp")
            let tripID = record.id
            let firstDate = record.isCompleted || record.isCancelled ? nil : record.reminderDateTime
            let secondDate = record.isCompleted || record.isCancelled ? nil : record.secondReminderDateTime
            let reminderFlight = SavedFlightDisplayContext(flightNumber: record.flightInfo, flightDate: record.flightDate,
                serviceType: record.serviceType, locationStart: record.locationStart, locationEnd: record.locationEnd,
                snapshot: record.flightSelectionSnapshotJSON.data(using: .utf8).flatMap { try? JSONDecoder().decode(SavedFlightSelection.self, from: $0) }, canDisplay: true).selection
            let reminderMessage = TripReminderMessage(serviceType: record.serviceType, flightNumber: record.flightInfo,
                flight: reminderFlight, customer: record.customerName, start: record.locationStart, end: record.locationEnd,
                appointmentDate: record.appointmentDate, appointmentTime: record.appointmentTime, locale: appLocale)
            Task {
                await TripReminderScheduler.schedule(
                    tripID: tripID,
                    firstDate: firstDate,
                    secondDate: secondDate,
                    locale: appLocale, message: reminderMessage
                )
            }
            dismiss()
            isPresented = false
        } catch {
            if booking == nil { modelContext.delete(record) }
            errorMessage = error.localizedDescription
        }
    }
}


// MARK: - 3. 子卡片模块组件细化

// 模块 1 布局
struct ServiceTypeSection: View {
    @Binding var formData: NewTripFormModel
    let services = [
        ("接机", "airplane.departure"), ("送机", "airplane.arrival"),
        ("接送", "car.fill"),("包车", "clock.fill"), ("转机", "ellipsis.circle.fill"),("其它", "ellipsis.circle.fill")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("行程类型")
                        .font(.subheadline.bold())
//                      .foregroundColor(.white)
//                    Text("按到达航班接客").font(.system(size: 11)).foregroundColor(.gray)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(services, id: \.0) { service, icon in
                    let isSelected = formData.serviceType == service
                    HStack(spacing: 6) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : icon)
                            .font(.system(size: 13))
                            .foregroundStyle(isSelected ? Color.green : Color.secondary)
                        Text(LocalizedStringKey(service))
                            .font(.system(size: 13))
//                          .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity).frame(height: 42)
//                    .background(Color(red: 0.11, green: 0.13, blue: 0.16))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.green.opacity(0.8) : Color.primary.opacity(0.14), lineWidth: isSelected ? 1.5 : 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { formData.serviceType = service } }
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10), lineWidth: 1))
//        .background(Color(red: 0.09, green: 0.10, blue: 0.12)).cornerRadius(14)
    }
}

// 模块 2 布局
struct QuickInputSection: View {
    @Binding var formData: NewTripFormModel
    @Environment(\.modelContext) private var context
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("智能粘贴", systemImage: "t.square").font(.subheadline.bold())
            SmartTripInput(text: $formData.quickInputText) { result in
                let scope = DataOwnership.activeScope
                let descriptor = FetchDescriptor<TravelAgency>(predicate: #Predicate { $0.ownerScope == scope })
                let matches = ((try? context.fetch(descriptor)) ?? []).filter { PickupAgencyMatcher.matches($0.name) && !$0.agencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                result.apply(to: &formData, agencyCode: matches.count == 1 ? matches.first?.agencyCode : nil)
                if result.pickupDateTime != nil, matches.count == 1, let agency = matches.first {
                    formData.travelAgencyName = agency.name
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }
}

// 模块 3 布局
struct OrderSourceSection: View {
    @Binding var formData: NewTripFormModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("订单来源").font(.subheadline.bold())
            HStack(spacing: 12) {
                let isNormal = formData.orderSource == "普通客户"
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: isNormal ? "person.fill" : "person")
                        .font(.system(size: 16))
                        .foregroundStyle(isNormal ? Color.accentColor : Color.secondary)
                    Text("普通客户").font(.system(size: 15, weight: .bold))
                    Text("熟客、散客或临时客人。").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(12).frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                .background(isNormal ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isNormal ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.12), lineWidth: isNormal ? 1.5 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 12)).onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { selectOrderSource("普通客户") } }
                
                let isPro = formData.orderSource == "旅行社订单"
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "building.2.fill").foregroundStyle(isPro ? Color.accentColor : Color.secondary)
                        Spacer()
                        if isPro { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                    }
                    Text("旅行社订单").font(.system(size: 15, weight: .bold))
                    Text("旅行社、地接或平台派单，记录订单号和联系人。").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(12).frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                .background(isPro ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(isPro ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.12), lineWidth: isPro ? 1.5 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 12)).onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { selectOrderSource("旅行社订单") } }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }

    private func selectOrderSource(_ source: String) {
        guard formData.orderSource != source else { return }
        formData.orderSource = source
        formData.travelAgencyCode = ""
        formData.travelAgencyName = ""
    }
}

struct TravelAgencyTripSection: View {
    @Binding var formData: NewTripFormModel
    @Query private var agencies: [TravelAgency]
    private var matchedAgency: TravelAgency? {
        guard !formData.travelAgencyCode.isEmpty else { return nil }
        let rows = agencies.filter { $0.ownerScope == DataOwnership.activeScope && $0.agencyCode == formData.travelAgencyCode }
        return rows.count == 1 ? rows.first : nil
    }
    @State private var isShowingAgencyPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("旅行社信息", systemImage: "building.2.fill")
                .font(.subheadline.weight(.semibold))
            Text("旅行社订单号").font(.caption).foregroundStyle(.secondary)
            SystemIMETextField(text: $formData.travelAgencyOrderNumber, placeholder: "输入旅行社提供的订单号", capitalization: .allCharacters, autocorrection: .no, fontSize: 14)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            Button { isShowingAgencyPicker = true } label: {
                VStack(alignment: .leading, spacing: 10) {
                    agencyValueRow(title: "旅行社代码", value: formData.travelAgencyCode)
                    Divider()
                    agencyValueRow(title: "旅行社名称", value: formData.travelAgencyName)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $isShowingAgencyPicker) {
                TravelAgencySelectionView { agency in
                    formData.travelAgencyCode = agency.agencyCode
                    formData.travelAgencyName = agency.name
                }
            }
            if let agency = matchedAgency {
                if !agency.contactPerson.isEmpty { LabeledContent("旅行社联系人", value: agency.contactPerson) }
                if !agency.phone.isEmpty { LabeledContent("旅行社电话", value: agency.phone) }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }

    private func agencyValueRow(title: String, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(title)).foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "点击选择" : value)
                .foregroundStyle(value.isEmpty ? Color.accentColor : Color.primary)
                .lineLimit(1)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .font(.system(size: 13, weight: .medium))
    }
}

// 模块 4 布局
struct CustomerSelectionSection: View {
    @Binding var formData: NewTripFormModel
    @Query private var customers: [Custumer]
    @State private var isShowingCustomerPicker = false
    @State private var selectedCustomerID: String?
    @State private var customerSearchText = ""

    init(formData: Binding<NewTripFormModel>) {
        self._formData = formData
        let scope = DataOwnership.activeScope
        _customers = Query(filter: #Predicate { $0.ownerScope == scope })
    }

    private var filteredCustomers: [Custumer] {
        let query = customerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return customers
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
                Label("客户:", systemImage: "person.2")
                .font(.subheadline.weight(.semibold))

            Text("客户")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack {
                SystemIMETextField(text: $formData.customerName, placeholder: "请输入客户姓名", fontSize: 14)
                    .onChange(of: formData.customerName) { _, newName in
                        guard let selectedID = formData.selectedCustomerUUID,
                              let selectedCustomer = customers.first(where: { $0.uuid == selectedID }),
                              newName.trimmingCharacters(in: .whitespacesAndNewlines) != selectedCustomer.name else { return }
                        formData.selectedCustomerUUID = nil
                    }
                    .padding(12)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                
                Button {
                    selectedCustomerID = nil
                    customerSearchText = ""
                    isShowingCustomerPicker = true
                } label: {
                    Image(systemName: "person.crop.rectangle.badge.plus.fill")
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .accessibilityLabel("选择客户")
                
            }
            Text("客户联系方式")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            SystemIMETextField(text: $formData.custemerConnect, placeholder: "请输入客户联系方式", keyboardType: .default, fontSize: 14)
                .padding(12)
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            HStack(spacing: 10){
                Label("人数", systemImage: "person")
                    .font(.caption.weight(.medium))
                SystemIMETextField(text: $formData.customerCount, placeholder: "1", keyboardType: .numberPad, fontSize: 14)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                Label("行李", systemImage: "suitcase")
                    .font(.caption.weight(.medium))
                SystemIMETextField(text: $formData.customerStuff, placeholder: "0", keyboardType: .numberPad, fontSize: 14)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            }

                           

            
        }
        .padding()
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10), lineWidth: 1))
        .sheet(isPresented: $isShowingCustomerPicker) {
            customerPicker
        }
    }

    private var customerPicker: some View {
        NavigationStack {
            Group {
                if filteredCustomers.isEmpty {
                    ContentUnavailableView(
                        customerSearchText.isEmpty ? "暂无客户" : "没有找到客户",
                        systemImage: "person.crop.rectangle",
                        description: Text(customerSearchText.isEmpty ? "请先在客户管理中添加客户。" : "请尝试其他客户名称。")
                    )
                } else {
                    List(filteredCustomers, id: \.uuid) { customer in
                        Button {
                            selectedCustomerID = customer.uuid
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(customer.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    if let contact = defaultContact(for: customer), !contact.connecttype.isEmpty {
                                        Text("\(contact.connectlable)  ·  \(contact.connecttype)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("未填写联系方式")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: selectedCustomerID == customer.uuid ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedCustomerID == customer.uuid ? Color.accentColor : Color.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                    .searchable(text: $customerSearchText, prompt: "搜索客户")
                }
            }
            .navigationTitle("选择客户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isShowingCustomerPicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") { applySelectedCustomer() }
                        .disabled(selectedCustomerID == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func defaultContact(for customer: Custumer) -> Connect? {
        customer.connecttype.first(where: \.isDefault) ?? customer.connecttype.first
    }

    private func applySelectedCustomer() {
        guard let id = selectedCustomerID,
              let customer = customers.first(where: { $0.uuid == id }) else { return }
        formData.customerName = customer.name
        formData.customerSelection = customer.name
        formData.selectedCustomerUUID = customer.uuid
        formData.custemerConnect = defaultContact(for: customer)?.connecttype ?? ""
        isShowingCustomerPicker = false
    }
}


// 模块 5 布局
struct TripDeteilSection: View {
    @Binding var formData: NewTripFormModel
    @ObservedObject var searcher: AddressAutocompleteSearcher
    @Environment(AuthViewModel.self) private var auth
    @Environment(\.openURL) private var openURL
    @State private var isShowingSuggestions = false
    @State private var suggestionTarget: AddressPickerTarget?
    @State private var suppressAutocompleteOnce = false
    @State private var focusedAddressField: AddressPickerTarget?
    @StateObject private var locationManager = TripCurrentLocationManager()
    @State private var currentLocationTarget: AddressPickerTarget = .start
    @Query private var customers: [Custumer]
    @State private var addressPickerTarget: AddressPickerTarget?
    @State private var selectedAddressIndex: Int?
    @State private var isLookingUpFlight = false
    @State private var flightLookupError: String?
    @State private var flightLookupTask: Task<Void, Never>?
    @State private var flightTimeZoneTask: Task<Void, Never>?
    @State private var flightLookupResult: VariFlightLookupResult?
    @State private var flightCandidates: [VariFlightLookupResult] = []
    @State private var isChoosingFlight = false
    @State private var departureTimeZoneLabel = ""
    @State private var arrivalTimeZoneLabel = ""

    init(formData: Binding<NewTripFormModel>, searcher: AddressAutocompleteSearcher) {
        self._formData = formData
        self.searcher = searcher
        let scope = DataOwnership.activeScope
        _customers = Query(filter: #Predicate { $0.ownerScope == scope })
    }

    private var selectedCustomerAddresses: [Address] {
        guard let customerID = formData.selectedCustomerUUID,
              let customer = customers.first(where: { $0.uuid == customerID }) else { return [] }
        return customer.addresses.sorted { $0.isDefault && !$1.isDefault }
    }

    private var flightLookupContextKey: String {
        [formData.flightInfo, String(formData.flightdate.timeIntervalSince1970), formData.serviceType, formData.locationStart, formData.locationEnd]
            .joined(separator: "\u{1F}")
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("行程详情", systemImage: "map")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("接载日期").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    DatePicker("接载日期", selection: $formData.appointmentDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("接载时间").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    DatePicker("接载时间", selection: $formData.appointmentTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("起始点", systemImage: "mappin.and.ellipse")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            let previousStart = formData.locationStart
                            formData.locationStart = formData.locationEnd
                            formData.locationEnd = previousStart
                            focusedAddressField = nil
                        }
                    } label: {
                        Label("互换", systemImage: "arrow.up.arrow.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("互换起始点和目的地")
                }
                addressInputRow(
                    $formData.locationStart,
                    target: .start,
                    placeholder: String(localized: "请输入客户的接载地点"),
                    addressBookLabel: "选择起始地址",
                    locationLabel: "获取起始点当前位置",
                    navigationLabel: "导航至起始点"
                )
            }

            if shouldShowSuggestions(for: .start) {
                addressSuggestions(for: .start)
            }

            ForEach(formData.locationStops.indices, id: \.self) { index in
                stopLocationField(at: index)
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    formData.locationStops.append("")
                }
                focusedAddressField = .stop(formData.locationStops.count - 1)
            } label: {
                Label("增加停靠点", systemImage: "plus.circle")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("目的地", systemImage: "flag.checkered")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                addressInputRow(
                    $formData.locationEnd,
                    target: .destination,
                    placeholder: String(localized: "请输入目的地"),
                    addressBookLabel: "选择目的地地址",
                    locationLabel: "获取目的地当前位置",
                    navigationLabel: "导航至目的地"
                )
            }

            if shouldShowSuggestions(for: .destination) {
                addressSuggestions(for: .destination)
            }
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("航班信息", systemImage: "airplane")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    FlightNumberTextField(text: $formData.flightInfo, placeholder: String(localized: "请输入航班号"), fontSize: 14)
                        .padding(10)
                        .frame(minHeight: 44)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Label("航班日期", systemImage: "calendar")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    DatePicker("", selection: $formData.flightdate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .tint(.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                }
                .frame(maxWidth: .infinity)
            }
            if auth.canQueryFlights {
                Button(action: lookupFlight) {
                    HStack(spacing: 8) {
                        if isLookingUpFlight { ProgressView().controlSize(.small) }
                        else { Image(systemName: "magnifyingglass") }
                        Text(isLookingUpFlight ? "正在查询航班" : "查询航班信息")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isLookingUpFlight || formData.flightInfo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Text("本地版可手动填写航班信息，并查看已保存的航班资料。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if isLookingUpFlight || flightLookupError != nil || flightLookupResult != nil {
                FlightInformationPanel(
                    flightNumber: formData.flightInfo,
                    flightDate: formData.flightdate,
                    result: flightLookupResult,
                    isLoading: isLookingUpFlight,
                    error: flightLookupError,
                    departureFallback: formData.flightDepartureTime,
                    arrivalFallback: formData.flightEstimatedArrivalTime,
                    departureTimeZone: departureTimeZoneLabel,
                    arrivalTimeZone: arrivalTimeZoneLabel
                )
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
        .padding()
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10), lineWidth: 1))
        .sheet(item: $addressPickerTarget) {
            addressPicker(for: $0)
        }
        .sheet(isPresented: $isChoosingFlight) {
            FlightCandidatePicker(candidates: flightCandidates, onSelect: selectFlight)
        }
        .onChange(of: focusedAddressField) { _, target in
            guard let target else {
                isShowingSuggestions = false
                return
            }
            let value: String
            switch target {
            case .start: value = formData.locationStart
            case .stop(let index): value = formData.locationStops.indices.contains(index) ? formData.locationStops[index] : ""
            case .destination: value = formData.locationEnd
            }
            suggestionTarget = target
            searcher.searchQuery = value
            isShowingSuggestions = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        .onChange(of: locationManager.resolvedAddress) { _, address in
            guard let address, !address.isEmpty else { return }
            setAddress(address, for: currentLocationTarget)
            focusedAddressField = nil
        }
        .onChange(of: locationManager.currentLocation) { _, location in
            guard let location else { return }
            searcher.updateRegion(center: location.coordinate)
        }
        .onChange(of: flightLookupContextKey) { _, _ in invalidateFlightSelection() }
        .alert("无法获取当前位置", isPresented: Binding(
            get: { locationManager.errorMessage != nil },
            set: { if !$0 { locationManager.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { locationManager.errorMessage = nil }
        } message: {
            Text(locationManager.errorMessage ?? "")
        }
    }

    private func addressInputRow(
        _ address: Binding<String>,
        target: AddressPickerTarget,
        placeholder: String,
        addressBookLabel: String,
        locationLabel: String,
        navigationLabel: String
    ) -> some View {
        VStack(spacing: 4) {
            SystemIMETextField(
                text: address, placeholder: placeholder, capitalization: .sentences,
                autocorrection: .default, fontSize: 14,
                isFocused: Binding(
                    get: { focusedAddressField == target },
                    set: { focused in
                        if focused { focusedAddressField = target }
                        else if focusedAddressField == target { focusedAddressField = nil }
                    }
                )
            )
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 38)

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button {
                    selectedAddressIndex = nil
                    addressPickerTarget = target
                } label: {
                    Image(systemName: "book.closed").frame(width: 34, height: 30)
                }
                .disabled(formData.selectedCustomerUUID == nil)
                .accessibilityLabel(addressBookLabel)

                Button {
                    currentLocationTarget = target
                    locationManager.requestCurrentLocation()
                } label: {
                    Image(systemName: "location.north.fill").frame(width: 34, height: 30)
                }
                .accessibilityLabel(locationLabel)

                Button { openNavigation(to: address.wrappedValue) } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill").frame(width: 34, height: 30)
                }
                .disabled(address.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(navigationLabel)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .onChange(of: address.wrappedValue) { _, value in
            addressInputDidChange(value, target: target)
        }
    }

    private func stopLocationField(at index: Int) -> some View {
        let target = AddressPickerTarget.stop(index)
        let address = Binding<String>(
            get: { formData.locationStops.indices.contains(index) ? formData.locationStops[index] : "" },
            set: { if formData.locationStops.indices.contains(index) { formData.locationStops[index] = $0 } }
        )

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("停靠点", systemImage: "mappin")
                Text("\(index + 1)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            addressInputRow(
                address,
                target: target,
                placeholder: String(localized: "请输入停靠点地址"),
                addressBookLabel: "选择停靠点地址",
                locationLabel: "获取停靠点当前位置",
                navigationLabel: "导航至停靠点"
            )

            HStack {
                Spacer()
                Button(role: .destructive) { removeStop(at: index) } label: {
                    Label("删除停靠点", systemImage: "minus.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }

            if shouldShowSuggestions(for: target) {
                addressSuggestions(for: target)
            }
        }
    }

    private func removeStop(at index: Int) {
        guard formData.locationStops.indices.contains(index) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            formData.locationStops.remove(at: index)
        }
        focusedAddressField = nil
        suggestionTarget = nil
        isShowingSuggestions = false
    }

    private func addressPicker(for target: AddressPickerTarget) -> some View {
        NavigationStack {
            Group {
                if selectedCustomerAddresses.isEmpty {
                    ContentUnavailableView(
                        "暂无常用地址",
                        systemImage: "mappin.and.ellipse",
                        description: Text("请先在该客户资料中添加常用地址，或直接手动输入。")
                    )
                } else {
                    List(Array(selectedCustomerAddresses.enumerated()), id: \.offset) { index, address in
                        Button {
                            selectedAddressIndex = index
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(address.addlable)
                                            .font(.subheadline.weight(.semibold))
                                        if address.isDefault {
                                            Text("默认")
                                                .font(.caption2.weight(.medium))
                                                .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    Text(address.addresses)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: selectedAddressIndex == index ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(selectedAddressIndex == index ? Color.accentColor : Color.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { addressPickerTarget = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") { applySelectedAddress(for: target) }
                        .disabled(selectedAddressIndex == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func applySelectedAddress(for target: AddressPickerTarget) {
        guard let index = selectedAddressIndex,
              selectedCustomerAddresses.indices.contains(index) else { return }
        let address = selectedCustomerAddresses[index].addresses
        setAddress(address, for: target)
        addressPickerTarget = nil
    }

    private func addressInputDidChange(_ value: String, target: AddressPickerTarget) {
        searcher.searchQuery = value
        if suppressAutocompleteOnce {
            suppressAutocompleteOnce = false
            isShowingSuggestions = false
            return
        }
        suggestionTarget = target
        isShowingSuggestions = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func shouldShowSuggestions(for target: AddressPickerTarget) -> Bool {
        isShowingSuggestions && focusedAddressField == target && suggestionTarget == target
    }

    private func addressSuggestions(for target: AddressPickerTarget) -> some View {
        let anchor = "local-address-suggestions-" + target.id
        return VStack(spacing: 0) {
            if searcher.isSearching {
                ProgressView("正在查找地址…").padding(12)
                    .id(searcher.completions.isEmpty ? anchor : anchor + "-loading")
            } else if searcher.errorMessage != nil {
                Text("地址联想暂不可用，请检查网络后重试。").font(.caption).padding(12).id(anchor)
                Button("重试") { searcher.retry() }.padding(.bottom, 8)
            } else if searcher.completions.isEmpty {
                Text("未找到地址，请补充城市或门牌号。").font(.caption).padding(12).id(anchor)
            }
            ForEach(Array(searcher.completions.prefix(5).enumerated()), id: \.offset) { index, completion in
                Button {
                    let address = [completion.title, completion.subtitle]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    setAddress(address, for: target)
                    focusedAddressField = nil
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(completion.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(index == min(1, searcher.completions.count - 1) ? anchor : anchor + "-row-\(index)")
                if completion.title != searcher.completions.prefix(5).last?.title {
                    Divider().padding(.leading, 42)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        .padding(.leading, 4)
        .padding(.trailing, 4)
        .preference(key: AddressSuggestionScrollPreference.self, value: AddressSuggestionScrollRequest(id: anchor, query: searcher.searchQuery, resultCount: searcher.completions.count, isSearching: searcher.isSearching))
    }

    private func setAddress(_ address: String, for target: AddressPickerTarget) {
        isShowingSuggestions = false
        suggestionTarget = nil
        searcher.searchQuery = address
        switch target {
        case .start:
            if formData.locationStart != address {
                suppressAutocompleteOnce = true
                formData.locationStart = address
            }
        case .stop(let index):
            if formData.locationStops.indices.contains(index), formData.locationStops[index] != address {
                suppressAutocompleteOnce = true
                formData.locationStops[index] = address
            }
        case .destination:
            if formData.locationEnd != address {
                suppressAutocompleteOnce = true
                formData.locationEnd = address
            }
        }
    }

    private func openNavigation(to address: String) {
        guard let url = NavigationProvider.selected.directionsURL(for: address) else { return }
        openURL(url)
    }

    private func lookupFlight() {
        guard auth.canQueryFlights else {
            flightLookupError = String(localized: "在线航班查询仅限云端版。", locale: AppLanguageSettings.currentLocale)
            return
        }
        let normalizedNumber = formData.flightInfo.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedNumber.isEmpty else { return }
        let lookupDate = formData.flightdate
        let lookupService = formData.serviceType
        let lookupStart = formData.locationStart
        let lookupEnd = formData.locationEnd
        let context = flightLookupContextKey
        flightLookupTask?.cancel()
        flightCandidates = []
        isChoosingFlight = false
        flightLookupResult = nil
        flightLookupError = nil
        isLookingUpFlight = true
        flightLookupTask = Task {
            defer {
                if !Task.isCancelled && context == flightLookupContextKey {
                    isLookingUpFlight = false
                    flightLookupTask = nil
                }
            }
            do {
                let cloudAccessToken: String?
                if auth.isCloudAccount {
                    cloudAccessToken = await auth.refreshCloudAccessToken() ?? auth.cloudAccessToken
                    guard cloudAccessToken != nil else { throw VariFlightClientError.missingCloudSession }
                } else { cloudAccessToken = nil }
                guard !Task.isCancelled, context == flightLookupContextKey else { return }
                let candidates = try await VariFlightClient().lookupCandidatesForTrip(
                    flightNumber: normalizedNumber,
                    flightDate: lookupDate,
                    serviceType: lookupService,
                    locationStart: lookupStart,
                    locationEnd: lookupEnd,
                    cloudAccessToken: cloudAccessToken
                )
                guard !Task.isCancelled, context == flightLookupContextKey else { return }
                flightCandidates = candidates
                if candidates.count == 1, let candidate = candidates.first,
                   !VariFlightClient.requiresExplicitFlightChoice(
                    serviceType: lookupService,
                    locationStart: lookupStart,
                    locationEnd: lookupEnd
                   ) {
                    selectFlight(candidate)
                } else {
                    isChoosingFlight = !candidates.isEmpty
                }
            } catch {
                guard !Task.isCancelled, context == flightLookupContextKey else { return }
                flightLookupError = error.localizedDescription
            }
        }
    }

    private func invalidateFlightSelection() {
        flightLookupTask?.cancel()
        flightLookupTask = nil
        flightTimeZoneTask?.cancel()
        flightTimeZoneTask = nil
        isLookingUpFlight = false
        flightCandidates = []
        isChoosingFlight = false
        flightLookupError = nil

        guard !formData.flightSelectionSnapshotJSON.isEmpty ||
              flightLookupResult != nil ||
              !formData.flightDepartureTime.isEmpty ||
              !formData.flightEstimatedArrivalTime.isEmpty ||
              !formData.flightArrivalTerminal.isEmpty ||
              !formData.flightBaggageCarousel.isEmpty ||
              !departureTimeZoneLabel.isEmpty ||
              !arrivalTimeZoneLabel.isEmpty else { return }
        formData.flightSelectionSnapshotJSON = ""
        flightLookupResult = nil
        flightLookupError = nil
        departureTimeZoneLabel = ""
        arrivalTimeZoneLabel = ""
        formData.flightDepartureTime = ""
        formData.flightEstimatedArrivalTime = ""
        formData.flightArrivalTerminal = ""
        formData.flightBaggageCarousel = ""
    }

    private func selectFlight(_ result: VariFlightLookupResult) {
        flightLookupResult = result
        formData.flightDepartureTime = result.departureTime ?? ""
        formData.flightEstimatedArrivalTime = result.estimatedArrivalTime ?? ""
        formData.flightArrivalTerminal = result.arrivalTerminal ?? ""
        formData.flightBaggageCarousel = result.baggageCarousel ?? ""
        let snapshot = SavedFlightSelection(flightNumber: formData.flightInfo, flightDate: formData.flightdate, selected: result)
        if let data = try? JSONEncoder().encode(snapshot) { formData.flightSelectionSnapshotJSON = String(decoding: data, as: UTF8.self) }
        flightTimeZoneTask?.cancel()
        let context = flightLookupContextKey
        let selectedDate = formData.flightdate
        departureTimeZoneLabel = ""
        arrivalTimeZoneLabel = ""
        flightTimeZoneTask = Task {
            let departure = await FlightTimeZoneResolver.label(for: result.departureAirport, date: selectedDate) ?? ""
            let arrival = await FlightTimeZoneResolver.label(for: result.arrivalAirport, date: selectedDate) ?? ""
            guard !Task.isCancelled, context == flightLookupContextKey else { return }
            departureTimeZoneLabel = departure
            arrivalTimeZoneLabel = arrival
            flightTimeZoneTask = nil
        }
    }
}

private enum AddressPickerTarget: Hashable, Identifiable {
    case start
    case stop(Int)
    case destination

    var id: String {
        switch self {
        case .start: "start"
        case .stop(let index): "stop-\(index)"
        case .destination: "destination"
        }
    }
    var title: String {
        switch self {
        case .start: "选择起始点"
        case .stop: "选择停靠点"
        case .destination: "选择目的地"
        }
    }
}


//// 模块 6 布局 行程费用信息
struct TripDeteilSectionMoney: View {
    @Binding var formData: NewTripFormModel
    @AppStorage(BaseCurrencyCatalog.countryCodeKey) private var baseCurrencyCountry = BaseCurrencyCatalog.defaultCountryCode

    private var currencySymbol: String {
        BaseCurrencyCatalog.option(for: baseCurrencyCountry).symbol
    }
    // 1. 数据模型中声明一个真实的 Double 变量（例如：订单金额）
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("费用与备注", systemImage: "dollarsign.circle")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("行程费用")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(currencySymbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    AmountTextField(placeholder: "0", value: $formData.TripPrice, fontSize: 14)
                        .frame(width: numericTextFieldWidth(for: formattedPrice, placeholder: "0"))
                }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(10)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                LimitedIMETextEditor(text: $formData.TripMemo, maxLength: 10000, fontSize: 14)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 96)
                    .padding(8)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            }
        }
        .padding()
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }

    private var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: formData.TripPrice)) ?? "0"
    }
}

private struct TripStatusSection: View {
    @Binding var formData: NewTripFormModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("状态信息", systemImage: "checkmark.circle")
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("行程状态", systemImage: "clock")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text("待执行")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Label("结算状态", systemImage: "banknote")
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Picker("结算状态", selection: $formData.isPaid) {
                        Text("未结款").tag(false)
                        Text("已结清").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("结算状态")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

private struct TripReminderSection: View {
    @Binding var formData: NewTripFormModel
    @State private var authorizationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("提醒", systemImage: "bell.badge")
                .font(.subheadline.weight(.semibold))

            Toggle(isOn: Binding(
                get: { formData.reminderEnabled },
                set: { setReminderEnabled($0) }
            )) {
                Text("自定义提醒")
                    .font(.subheadline)
            }
            .tint(.accentColor)

            if formData.reminderEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("提醒时间")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    reminderDateTimePickers(
                        dateTime: $formData.reminderDateTime,
                        onChange: { formData.reminderDateWasCustomized = true }
                    )
                    Text(LocalizedStringKey(formData.copiedReminderDefaultsToTwoHours
                        ? "默认提前2小时；临近行程自动调整"
                        : "默认前一天；临近行程自动调整到未来时间"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))

                if formData.hasSecondReminder {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("第二次提醒")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    formData.hasSecondReminder = false
                                }
                            } label: {
                                Label("移除", systemImage: "minus.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        reminderDateTimePickers(
                            dateTime: $formData.secondReminderDateTime,
                            onChange: { formData.secondReminderDateWasCustomized = true }
                        )
                        Text("默认提前2小时；临近行程自动调整")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            formData.hasSecondReminder = true
                            formData.secondReminderDateWasCustomized = false
                            formData.updateDefaultReminderDateTimes()
                        }
                    } label: {
                        Label("添加第二次提醒", systemImage: "plus.circle")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                }
            } else {
                Text("开启后，行程管家会在设定时间发送系统通知。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10), lineWidth: 1))
        .animation(.easeInOut(duration: 0.18), value: formData.reminderEnabled)
        .alert("无法启用提醒", isPresented: Binding(
            get: { authorizationMessage != nil },
            set: { if !$0 { authorizationMessage = nil } }
        )) {
            Button("确定", role: .cancel) { authorizationMessage = nil }
        } message: {
            Text(authorizationMessage ?? "")
        }
    }

    @ViewBuilder
    private func reminderDateTimePickers(dateTime: Binding<Date>, onChange: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("日期").font(.caption2).foregroundStyle(.secondary)
                DatePicker("日期", selection: dateTime, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 42)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .simultaneousGesture(TapGesture().onEnded { onChange() })
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("时间").font(.caption2).foregroundStyle(.secondary)
                DatePicker("时间", selection: dateTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 42)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .simultaneousGesture(TapGesture().onEnded { onChange() })
            }
        }
    }

    private func setReminderEnabled(_ enabled: Bool) {
        guard enabled else {
            formData.reminderEnabled = false
            return
        }

        Task {
            do {
                let allowed = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                if allowed {
                    formData.updateDefaultReminderDateTimes()
                    formData.reminderEnabled = true
                } else {
                    authorizationMessage = String(localized: "请在 iPhone 设置中允许行程管家发送通知。", locale: AppLanguageSettings.currentLocale)
                }
            } catch {
                authorizationMessage = String(localized: "无法启用提醒，请稍后重试。", locale: AppLanguageSettings.currentLocale)
            }
        }
    }
}

struct TripReminderMessage {
    let title: String
    let details: String
    let pickup: Date
    let locale: Locale

    init(serviceType: String, flightNumber: String, flight: VariFlightLookupResult?, customer: String,
         start: String, end: String, appointmentDate: Date, appointmentTime: Date, locale: Locale,
         calendar: Calendar = .current) {
        self.locale = locale
        let day = calendar.dateComponents([.year, .month, .day], from: appointmentDate)
        let clock = calendar.dateComponents([.hour, .minute], from: appointmentTime)
        pickup = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: clock.hour, minute: clock.minute)) ?? appointmentDate
        func clean(_ value: String?) -> String { (value ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        func airport(_ name: String?, _ terminal: String?) -> String {
            let name = clean(name), terminal = clean(terminal)
            guard !name.isEmpty else { return "" }
            guard !terminal.isEmpty else { return name }
            let label = terminal.allSatisfy(\.isNumber) ? "T" + terminal : terminal
            return name + " " + label
        }
        let route = [airport(flight?.departureAirport, flight?.departureTerminal), airport(flight?.arrivalAirport, flight?.arrivalTerminal)]
        let flightRoute = route.allSatisfy { !$0.isEmpty } ? route.joined(separator: " → ") : ""
        let type = clean(serviceType)
        title = String(localized: "行程管家", locale: locale)
        let tripSummary = (type.isEmpty ? "" : "[" + type + "]")
            + [clean(flightNumber).uppercased(), flightRoute].filter { !$0.isEmpty }.map { " " + $0 }.joined()
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M/d HH:mm"
        let addresses = [clean(start), clean(end)].filter { !$0.isEmpty }.joined(separator: " → ")
        details = [tripSummary, formatter.string(from: pickup), clean(customer), addresses].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    func body(at reminderDate: Date) -> String {
        let minutes = Int(ceil(pickup.timeIntervalSince(reminderDate) / 60))
        guard minutes > 0 else { return details }
        let remaining = minutes % 60 == 0
            ? String(localized: "距接客约 \(minutes / 60) 小时", locale: locale)
            : String(localized: "距接客约 \(minutes) 分钟", locale: locale)
        return details + " · " + remaining
    }
}

extension TripReminderMessage {
    private static func cloudDate(_ value: String) -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .distantPast
    }
    init(booking: TripBookingRecord, locale: Locale) {
        let snapshot = (try? JSONDecoder().decode(SavedFlightSelection.self, from: Data(booking.flightSelectionSnapshotJSON.utf8)))
        let flight = SavedFlightDisplayContext(flightNumber: booking.flightInfo, flightDate: booking.flightDate,
            serviceType: booking.serviceType, locationStart: booking.locationStart, locationEnd: booking.locationEnd,
            snapshot: snapshot, canDisplay: true).selection
        self.init(serviceType: booking.serviceType, flightNumber: booking.flightInfo, flight: flight,
            customer: booking.customerName, start: booking.locationStart, end: booking.locationEnd,
            appointmentDate: booking.appointmentDate, appointmentTime: booking.appointmentTime, locale: locale)
    }
    init(trip: CloudOnlineRepository.CloudTripRecord, locale: Locale) {
        let flight = SavedFlightDisplayContext(flightNumber: trip.flightInfo, flightDate: Self.cloudDate(trip.flightDate),
            serviceType: trip.serviceType, locationStart: trip.locationStart, locationEnd: trip.locationEnd,
            snapshot: trip.flightSelectionSnapshot, canDisplay: true).selection
        self.init(serviceType: trip.serviceType, flightNumber: trip.flightInfo, flight: flight,
            customer: trip.customerName, start: trip.locationStart, end: trip.locationEnd,
            appointmentDate: Self.cloudDate(trip.appointmentDate), appointmentTime: Self.cloudDate(trip.appointmentTime), locale: locale)
    }
}

enum TripReminderScheduler {
    static func identifiers(for tripID: UUID) -> [String] {
        ["trip-reminder-\(tripID.uuidString)-1", "trip-reminder-\(tripID.uuidString)-2"]
    }

    static func cancel(tripID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers(for: tripID))
    }

    /// Upgrade only existing pending notifications; never recreate disabled or delivered reminders.
    @MainActor static func refreshPendingMessages(_ messages: [UUID: TripReminderMessage], isCurrent: @MainActor () -> Bool = { !Task.isCancelled }) async {
        guard !messages.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        guard isCurrent() else { return }
        for request in requests {
            guard isCurrent() else { return }
            guard let match = messages.first(where: { identifiers(for: $0.key).contains(request.identifier) }),
                  let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() ?? (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate(), date > .now,
                  let content = request.content.mutableCopy() as? UNMutableNotificationContent else { continue }
            let message = match.value
            guard content.title != message.title || content.body != message.body(at: date) else { continue }
            content.title = message.title
            content.body = message.body(at: date)
            try? await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: request.trigger))
        }
    }

    /// Persist an absolute instant so timezone changes and the repeated DST hour
    /// cannot move a previously chosen reminder to a different occurrence.
    static func trigger(for date: Date) -> UNCalendarNotificationTrigger {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }

    static func schedule(tripID: UUID, firstDate: Date?, secondDate: Date?, locale: Locale, message: TripReminderMessage) async {
        let center = UNUserNotificationCenter.current()
        let firstID = "trip-reminder-\(tripID.uuidString)-1"
        let secondID = "trip-reminder-\(tripID.uuidString)-2"
        center.removePendingNotificationRequests(withIdentifiers: [firstID, secondID])

        let reminders = [(firstID, firstDate), (secondID, secondDate)]
        for (identifier, date) in reminders {
            guard let date, date > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = message.title
            content.body = message.body(at: date)
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "trip-reminder-chime.caf"))

            let trigger = trigger(for: date)
            do {
                try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            } catch {
                print("行程提醒安排失败：\(error.localizedDescription)")
            }
        }
    }
}

final class TripNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TripNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}

// MARK: - 4. 完美的 Canvas 实时验证预览块
//#Preview {
//    AddTripFormView()
//}
#Preview {
    // 💡 在本地沙盒内直接喂一个假的常量 true，让 Canvas 稳定独立渲染
    AddTripFormView(isPresented: .constant(true))
        .modelContainer(for: TripBookingRecord.self, inMemory: true)
}



// MARK: - 7. 现代原生地址自动匹配引擎
class AddressAutocompleteSearcher: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchQuery = "" {
        didSet {
            guard normalized(searchQuery) != normalized(oldValue) else { return }
            cancelCurrentRequest()
            let query = normalized(searchQuery)
            completions = cachedResults[query] ?? []
            errorMessage = nil
            isSearching = !query.isEmpty && cachedResults[query] == nil
        }
    }
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private let makeCompleter: () -> MKLocalSearchCompleter
    private var completer: MKLocalSearchCompleter?
    private var activeQuery = ""
    private var cachedResults: [String: [MKLocalSearchCompletion]] = [:]
    private var region: MKCoordinateRegion?
    private var cancellable: AnyCancellable?

    override convenience init() {
        self.init(makeCompleter: { MKLocalSearchCompleter() })
    }

    init(makeCompleter: @escaping () -> MKLocalSearchCompleter) {
        self.makeCompleter = makeCompleter
        super.init()
        cancellable = $searchQuery
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .removeDuplicates()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in self?.request(query) }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cancelCurrentRequest() {
        completer?.delegate = nil
        completer?.cancel()
        completer = nil
        activeQuery = ""
    }

    private func request(_ query: String) {
        guard query == normalized(searchQuery), !query.isEmpty else { return }
        if let cached = cachedResults[query] {
            completions = cached
            isSearching = false
            return
        }
        // A new completer also retries a previously cancelled identical query.
        // Apple need not send another callback when an existing queryFragment is unchanged.
        cancelCurrentRequest()
        let next = makeCompleter()
        next.delegate = self
        next.resultTypes = [.address, .pointOfInterest]
        if let region { next.region = region }
        completer = next
        activeQuery = query
        errorMessage = nil
        isSearching = true
        next.queryFragment = query
    }

    func retry() {
        let query = normalized(searchQuery)
        guard !query.isEmpty else { return }
        cachedResults.removeValue(forKey: query)
        request(query)
    }

    func updateRegion(center: CLLocationCoordinate2D) {
        region = MKCoordinateRegion(center: center, latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        cachedResults.removeAll()
        cancelCurrentRequest()
        completions = []
        request(normalized(searchQuery))
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            guard self.completer === completer,
                  self.activeQuery == self.normalized(self.searchQuery) else { return }
            let results = completer.results
            if self.cachedResults.count >= 20 { self.cachedResults.removeAll() }
            self.cachedResults[self.activeQuery] = results
            self.completions = results
            self.isSearching = false
            self.errorMessage = nil
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async {
            guard self.completer === completer,
                  self.activeQuery == self.normalized(self.searchQuery) else { return }
            self.completions = []
            self.isSearching = false
            self.errorMessage = error.localizedDescription
        }
    }
}

@MainActor
final class TripCurrentLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var resolvedAddress: String?
    @Published var errorMessage: String?

    private let manager = CLLocationManager()
    private var reverseGeocodingRequest: MKReverseGeocodingRequest?
    private var isWaitingForExplicitAuthorization = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentLocation() {
        errorMessage = nil
        resolvedAddress = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            isWaitingForExplicitAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            isWaitingForExplicitAuthorization = false
            manager.requestLocation()
        case .denied, .restricted:
            isWaitingForExplicitAuthorization = false
            errorMessage = String(localized: "请在 iPhone 设置中允许行程管家使用定位服务。", locale: AppLanguageSettings.currentLocale)
        @unknown default:
            errorMessage = String(localized: "当前无法使用定位服务。", locale: AppLanguageSettings.currentLocale)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            // CLLocationManager can notify us just because the editor opened.
            // Only fetch a location when the user explicitly tapped the location button.
            guard isWaitingForExplicitAuthorization else { return }
            isWaitingForExplicitAuthorization = false
            manager.requestLocation()
        case .denied, .restricted:
            guard isWaitingForExplicitAuthorization else { return }
            isWaitingForExplicitAuthorization = false
            errorMessage = String(localized: "请在 iPhone 设置中允许行程管家使用定位服务。", locale: AppLanguageSettings.currentLocale)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            errorMessage = String(localized: "未能获取当前位置，请稍后重试。", locale: AppLanguageSettings.currentLocale)
            return
        }
        currentLocation = location
        reverseGeocodingRequest?.cancel()
        guard let request = MKReverseGeocodingRequest(location: location) else {
            errorMessage = String(localized: "无法解析当前位置，请手动输入地址。", locale: AppLanguageSettings.currentLocale)
            return
        }
        reverseGeocodingRequest = request
        request.getMapItems { [weak self] mapItems, error in
            guard let self else { return }
            if let mapItem = mapItems?.first {
                let address = mapItem.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
                    ?? mapItem.name
                    ?? ""
                if !address.isEmpty {
                    self.resolvedAddress = address
                    return
                }
            }
            if error != nil {
                self.errorMessage = String(localized: "地址解析失败，请手动输入地址。", locale: AppLanguageSettings.currentLocale)
            } else {
                self.errorMessage = String(localized: "未能识别当前位置的地址，请手动输入。", locale: AppLanguageSettings.currentLocale)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = String(localized: "定位失败，请检查定位权限后重试。", locale: AppLanguageSettings.currentLocale)
    }
}
