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
// MARK: - 1. 本地安全行程数据模型
struct NewTripFormModel {
    var id: UUID = .init()
    var serviceType: String = "接机"
    var quickInputText: String = ""
    var orderSource: String = "普通客户"
    var travelAgencyCode: String = ""
    var travelAgencyName: String = ""
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

        if !reminderDateWasCustomized {
            reminderDateTime = copiedReminderDefaultsToTwoHours
                ? (Calendar.current.date(byAdding: .hour, value: -2, to: appointment) ?? appointment)
                : (Calendar.current.date(byAdding: .day, value: -1, to: appointment) ?? appointment)
        }
        if !secondReminderDateWasCustomized {
            secondReminderDateTime = Calendar.current.date(byAdding: .hour, value: -2, to: appointment) ?? appointment
        }
    }

    mutating func adjustRemindersForAppointmentChange() {
        var appointmentComponents = Calendar.current.dateComponents([.year, .month, .day], from: appointmentDate)
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: appointmentTime)
        appointmentComponents.hour = timeComponents.hour
        appointmentComponents.minute = timeComponents.minute
        let appointment = Calendar.current.date(from: appointmentComponents) ?? appointmentDate

        reminderDateTime = Calendar.current.date(byAdding: .day, value: -1, to: appointment) ?? appointment
        secondReminderDateTime = Calendar.current.date(byAdding: .hour, value: -2, to: appointment) ?? appointment
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
                ScrollView {
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
                }
                .scrollDismissesKeyboard(.interactively)
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
            let firstDate = record.reminderDateTime
            let secondDate = record.secondReminderDateTime
            Task {
                await TripReminderScheduler.schedule(
                    tripID: tripID,
                    firstDate: firstDate,
                    secondDate: secondDate,
                    locale: appLocale
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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack{
                Image(systemName: "t.square")
                Text("智能粘贴").font(.subheadline.bold())
            }
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    LimitedIMETextEditor(text: $formData.quickInputText, maxLength: 5000, fontSize: 14)
                        .frame(height: 90).padding(10)
                        .cornerRadius(10)
                    if formData.quickInputText.isEmpty {
                        Text("例如：明天晚上 9 点半 接机 UA123 张先生 送到市中心")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary).lineSpacing(5)
                            .padding(.horizontal, 14).padding(.vertical, 16).allowsHitTesting(false)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    }
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
    @State private var isShowingAgencyPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("旅行社信息", systemImage: "building.2.fill")
                .font(.subheadline.weight(.semibold))
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
    @Environment(\.openURL) private var openURL
    @State private var isShowingSuggestions = false
    @State private var suggestionTarget: AddressPickerTarget?
    @State private var suppressAutocompleteOnce = false
    @FocusState private var focusedAddressField: AddressPickerTarget?
    @StateObject private var locationManager = TripCurrentLocationManager()
    @State private var currentLocationTarget: AddressPickerTarget = .start
    @Query private var customers: [Custumer]
    @State private var addressPickerTarget: AddressPickerTarget?
    @State private var selectedAddressIndex: Int?
    @State private var isLookingUpFlight = false
    @State private var flightLookupError: String?
    @State private var flightLookupResult: VariFlightLookupResult?
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
                HStack(spacing: 8) {
                LimitedIMETextEditor(text: $formData.locationStart, maxLength: 1000, fontSize: 14, placeholder: String(localized: "请输入客户的接载地点"), isFocused: addressFocusBinding(for: .start))
                    .padding(10)
                    .frame(minHeight: 44, maxHeight: 90)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .onChange(of: formData.locationStart) { _, value in
                        addressInputDidChange(value, target: .start)
                    }

                    Button {
                        selectedAddressIndex = nil
                        addressPickerTarget = .start
                    } label: {
                        Image(systemName: "book.closed")
                    }
                    .disabled(formData.selectedCustomerUUID == nil)
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .accessibilityLabel("选择起始地址")

                    Button {
                        currentLocationTarget = .start
                        locationManager.requestCurrentLocation()
                    } label: {
                        Image(systemName: "location.north.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .accessibilityLabel("获取起始点当前位置")

                    Button {
                    openNavigation(to: formData.locationStart)
                    } label: {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .accessibilityLabel("导航至起始点")
                    .disabled(formData.locationStart.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
                HStack(spacing: 8) {
                LimitedIMETextEditor(text: $formData.locationEnd, maxLength: 1000, fontSize: 14, placeholder: String(localized: "请输入目的地"), isFocused: addressFocusBinding(for: .destination))
                    .frame(minHeight: 44, maxHeight: 90)
                    .padding(10)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .onChange(of: formData.locationEnd) { _, value in
                        addressInputDidChange(value, target: .destination)
                    }
                
                Button {
                        selectedAddressIndex = nil
                        addressPickerTarget = .destination
                } label: {
                    Image(systemName: "book.closed")
                }
                .disabled(formData.selectedCustomerUUID == nil)
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .accessibilityLabel("选择目的地地址")

                Button {
                    currentLocationTarget = .destination
                    locationManager.requestCurrentLocation()
                } label: {
                    Image(systemName: "location.north.fill")
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .accessibilityLabel("获取目的地当前位置")

                Button {
                    openNavigation(to: formData.locationEnd)
                } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .accessibilityLabel("导航至目的地")
                .disabled(formData.locationEnd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
            searcher.completions = []
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
        .alert("无法获取当前位置", isPresented: Binding(
            get: { locationManager.errorMessage != nil },
            set: { if !$0 { locationManager.errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { locationManager.errorMessage = nil }
        } message: {
            Text(locationManager.errorMessage ?? "")
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
            HStack(spacing: 8) {
                    LimitedIMETextEditor(text: address, maxLength: 1000, fontSize: 14, placeholder: String(localized: "请输入停靠点地址"), isFocused: addressFocusBinding(for: target))
                    .frame(minHeight: 44, maxHeight: 90)
                    .padding(10)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .onChange(of: address.wrappedValue) { _, value in
                        addressInputDidChange(value, target: target)
                    }

                Button {
                        selectedAddressIndex = nil
                        addressPickerTarget = target
                } label: {
                    Image(systemName: "book.closed")
                }
                .disabled(formData.selectedCustomerUUID == nil)
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .accessibilityLabel("选择停靠点地址")

                Button {
                    currentLocationTarget = target
                    locationManager.requestCurrentLocation()
                } label: {
                    Image(systemName: "location.north.fill")
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .accessibilityLabel("获取停靠点当前位置")

                Button { openNavigation(to: address.wrappedValue) } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .accessibilityLabel("导航至停靠点")
                .disabled(address.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

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

    private func addressFocusBinding(for target: AddressPickerTarget) -> Binding<Bool> {
        Binding(
            get: { focusedAddressField == target },
            set: { isFocused in
                if isFocused {
                    focusedAddressField = target
                } else if focusedAddressField == target {
                    focusedAddressField = nil
                }
            }
        )
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
        searcher.completions = []
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
        isShowingSuggestions && suggestionTarget == target && !searcher.completions.isEmpty
    }

    private func addressSuggestions(for target: AddressPickerTarget) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(searcher.completions.enumerated()), id: \.offset) { _, completion in
                Button {
                    let address = [completion.title, completion.subtitle]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
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
                if completion.title != searcher.completions.last?.title {
                    Divider().padding(.leading, 42)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        .padding(.leading, 4)
        .padding(.trailing, 4)
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
        flightLookupError = nil
        flightLookupResult = nil
        isLookingUpFlight = true
        Task {
            defer { isLookingUpFlight = false }
            do {
                let result = try await VariFlightClient().lookup(
                    flightNumber: formData.flightInfo,
                    flightDate: formData.flightdate
                )
                flightLookupResult = result
                formData.flightDepartureTime = result.departureTime ?? ""
                formData.flightEstimatedArrivalTime = result.estimatedArrivalTime ?? ""
                formData.flightArrivalTerminal = result.arrivalTerminal ?? ""
                formData.flightBaggageCarousel = result.baggageCarousel ?? ""
                departureTimeZoneLabel = await FlightTimeZoneResolver.label(for: result.departureAirport, date: formData.flightdate) ?? ""
                arrivalTimeZoneLabel = await FlightTimeZoneResolver.label(for: result.arrivalAirport, date: formData.flightdate) ?? ""
            } catch {
                flightLookupError = error.localizedDescription
            }
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
                }
                    .padding(10)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                LimitedIMETextEditor(text: $formData.TripMemo, maxLength: 10000, fontSize: 14)
                    .frame(minHeight: 96)
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
                        ? "默认：接载时间前 2 小时"
                        : "默认：接载日期前一天的同一时间"))
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
                        Text("默认：接载时间前 2 小时")
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
                    authorizationMessage = "请在 iPhone 设置中允许行程管家发送通知。"
                }
            } catch {
                authorizationMessage = error.localizedDescription
            }
        }
    }
}

private enum TripReminderScheduler {
    static func schedule(tripID: UUID, firstDate: Date?, secondDate: Date?, locale: Locale) async {
        let center = UNUserNotificationCenter.current()
        let firstID = "trip-reminder-\(tripID.uuidString)-1"
        let secondID = "trip-reminder-\(tripID.uuidString)-2"
        center.removePendingNotificationRequests(withIdentifiers: [firstID, secondID])

        let reminders = [(firstID, firstDate), (secondID, secondDate)]
        for (identifier, date) in reminders {
            guard let date, date > .now else { continue }

            let content = UNMutableNotificationContent()
            content.title = String(localized: "行程提醒", locale: locale)
            content.body = String(localized: "您有一个即将开始的行程。", locale: locale)
            content.sound = .default

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
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
    @Published var searchQuery = ""
    @Published var completions: [MKLocalSearchCompletion] = []
    
    private var completer = MKLocalSearchCompleter()
    private var cancellable: AnyCancellable?
    
    override init() {
        super.init()
        completer.delegate = self
        // 限制匹配类型为：具体地址及兴趣点（如机场、酒店、火车站），完美对齐接送机业务
        completer.resultTypes = [.address, .pointOfInterest]
        
        // 节流机制：防止打字太快导致高频重复向系统发起地理请求
        cancellable = $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] query in
                if query.isEmpty {
                    self?.completions = []
                } else {
                    self?.completer.queryFragment = query
                }
            }
    }

    func updateRegion(center: CLLocationCoordinate2D) {
        completer.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 30_000,
            longitudinalMeters: 30_000
        )
    }
    
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async { self.completions = completer.results }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("地址自动匹配补全失败: \(error.localizedDescription)")
    }
}

@MainActor
final class TripCurrentLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var resolvedAddress: String?
    @Published var errorMessage: String?

    private let manager = CLLocationManager()
    private var reverseGeocodingRequest: MKReverseGeocodingRequest?

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
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            errorMessage = "请在 iPhone 设置中允许行程管家使用定位服务。"
        @unknown default:
            errorMessage = "当前无法使用定位服务。"
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            errorMessage = "请在 iPhone 设置中允许行程管家使用定位服务。"
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            errorMessage = "未能获取当前位置，请稍后重试。"
            return
        }
        currentLocation = location
        reverseGeocodingRequest?.cancel()
        guard let request = MKReverseGeocodingRequest(location: location) else {
            errorMessage = "无法解析当前位置，请手动输入地址。"
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
            if let error {
                self.errorMessage = "地址解析失败：\(error.localizedDescription)"
            } else {
                self.errorMessage = "未能识别当前位置的地址，请手动输入。"
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        errorMessage = "定位失败：\(error.localizedDescription)"
    }
}
