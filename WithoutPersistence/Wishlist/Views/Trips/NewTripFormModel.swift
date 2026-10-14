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
    var customerSelection: String = "客户选择"
    var selectedCustomerUUID: String?
    var customerName: String = ""
    var custemerConnect: String = ""
    var customerCount: String = "1"
    var customerStuff: String = "0"
    var appointmentDate: Date = Date()
    var appointmentTime: Date = Date()
    var locationStart: String = ""
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

    mutating func updateDefaultReminderDateTimes() {
        var appointmentComponents = Calendar.current.dateComponents([.year, .month, .day], from: appointmentDate)
        let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: appointmentTime)
        appointmentComponents.hour = timeComponents.hour
        appointmentComponents.minute = timeComponents.minute
        let appointment = Calendar.current.date(from: appointmentComponents) ?? appointmentDate

        if !reminderDateWasCustomized {
            reminderDateTime = Calendar.current.date(byAdding: .day, value: -1, to: appointment) ?? appointment
        }
        if !secondReminderDateWasCustomized {
            secondReminderDateTime = Calendar.current.date(byAdding: .hour, value: -2, to: appointment) ?? appointment
        }
    }
}

@Model
final class TripBookingRecord {
    @Attribute(.unique) var id: UUID
    var serviceType: String
    var orderSource: String
    var customerName: String
    var customerContact: String
    var customerCount: String
    var customerStuff: String
    var appointmentDate: Date
    var appointmentTime: Date
    var locationStart: String
    var locationEnd: String
    var flightInfo: String
    var flightDate: Date
    var flightDepartureTime: String?
    var flightEstimatedArrivalTime: String?
    var flightArrivalTerminal: String?
    var flightBaggageCarousel: String?
    var memo: String
    var price: Double
    var isPaid: Bool
    var isCompleted: Bool
    var reminderEnabled: Bool = false
    var reminderDateTime: Date?
    var hasSecondReminder: Bool = false
    var secondReminderDateTime: Date?
    var createdAt: Date

    init(form: NewTripFormModel) {
        id = form.id
        serviceType = form.serviceType
        orderSource = form.orderSource
        customerName = form.customerName
        customerContact = form.custemerConnect
        customerCount = form.customerCount
        customerStuff = form.customerStuff
        appointmentDate = form.appointmentDate
        appointmentTime = form.appointmentTime
        locationStart = form.locationStart
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
        reminderEnabled = form.reminderEnabled
        reminderDateTime = form.reminderEnabled ? form.reminderDateTime : nil
        let shouldScheduleSecondReminder = form.reminderEnabled && form.hasSecondReminder
        hasSecondReminder = shouldScheduleSecondReminder
        secondReminderDateTime = shouldScheduleSecondReminder ? form.secondReminderDateTime : nil
        createdAt = .now
    }
}

// MARK: - 2. 主页面视图（支持 Canvas 完美双向独立预览）
struct AddTripFormView: View {
    @Environment(\.dismiss) private var dismiss // 用于关闭页面
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var appLocale
    @State private var formData = NewTripFormModel()
    @Binding var isPresented: Bool
    @State private var errorMessage: String?
    // 实例化地址联想核心状态机
    @StateObject private var searcher = AddressAutocompleteSearcher()


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
                .onChange(of: formData.appointmentDate) { _, _ in formData.updateDefaultReminderDateTimes() }
                .onChange(of: formData.appointmentTime) { _, _ in formData.updateDefaultReminderDateTimes() }
                .navigationTitle("新增行程")
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
        let record = TripBookingRecord(form: formData)
        modelContext.insert(record)
        do {
            try modelContext.save()
            UserDefaults.standard.set(formData.appointmentDate.timeIntervalSince1970, forKey: "tripList.selectedDateTimestamp")
            if record.reminderEnabled {
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
            }
            dismiss()
            isPresented = false
        } catch {
            modelContext.delete(record)
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
                    TextEditor(text: $formData.quickInputText)
                        .font(.system(size: 14))
                        .nativeIMEInput()
                        .scrollContentBackground(.hidden)
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
                .contentShape(RoundedRectangle(cornerRadius: 12)).onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { formData.orderSource = "普通客户" } }
                
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
                .contentShape(RoundedRectangle(cornerRadius: 12)).onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { formData.orderSource = "旅行社订单" } }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }
}

// 模块 4 布局
struct CustomerSelectionSection: View {
    @Binding var formData: NewTripFormModel
    @Query private var customers: [Custumer]
    @State private var isShowingCustomerPicker = false
    @State private var selectedCustomerID: String?
    @State private var customerSearchText = ""

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
                TextField("", text: $formData.customerName, prompt: Text("请输入客户姓名").foregroundStyle(.secondary))
                    .font(.system(size: 14))
                    .nativeIMEInput()
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
            TextField("", text: $formData.custemerConnect, prompt: Text("请输入客户联系方式").foregroundStyle(.secondary))
                               .font(.system(size: 14))
                               .nativeIMEInput()
                               .padding(12)
                               .cornerRadius(10)
                               .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            HStack(spacing: 10){
                Label("人数", systemImage: "person")
                    .font(.caption.weight(.medium))
                TextField("1", text: $formData.customerCount, prompt: Text("请输入客户联系方式").foregroundStyle(.secondary))
                                   .font(.system(size: 14))
                                   .padding(.horizontal, 10)
                                   .frame(height: 44)
                                   .cornerRadius(10)
                                   .keyboardType(.numberPad)
                                   .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                Label("行李", systemImage: "suitcase")
                    .font(.caption.weight(.medium))
                TextField("0", text: $formData.customerStuff, prompt: Text("请输入客户联系方式").foregroundStyle(.secondary))
                                   .font(.system(size: 14))
                                   .padding(.horizontal, 10)
                                   .frame(height: 44)
                                   .cornerRadius(10)
                                   .keyboardType(.numberPad)
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
                Label("起始点", systemImage: "mappin.and.ellipse")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                TextField("", text: $formData.locationStart, prompt: Text("请输入客户的接载地点").foregroundStyle(.secondary),axis: .vertical)
                    .font(.system(size: 14))
                    .nativeIMEInput()
                    .focused($focusedAddressField, equals: .start)
                    .padding(10)
                    .lineLimit(3)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .onChange(of: formData.locationStart) { _, value in
                        addressInputDidChange(value, target: .start)
                    }

                    Menu {
                    Button {
                        selectedAddressIndex = nil
                        addressPickerTarget = .start
                    } label: {
                        Label("选择客户常用地址", systemImage: "book.closed")
                    }
                    .disabled(formData.selectedCustomerUUID == nil)

                    Button {
                        currentLocationTarget = .start
                        locationManager.requestCurrentLocation()
                    } label: {
                        Label("使用当前位置", systemImage: "location.fill")
                    }
                    } label: {
                        Image(systemName: "book.closed")
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .accessibilityLabel("选择起始地址")

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
            
            VStack(alignment: .leading, spacing: 8) {
                Label("目的地", systemImage: "flag.checkered")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                TextField("", text: $formData.locationEnd, prompt: Text("请输入目的地").foregroundStyle(.secondary),axis: .vertical)
                    .lineLimit(3)
                    .font(.system(size: 14))
                    .nativeIMEInput()
                    .focused($focusedAddressField, equals: .destination)
                    .padding(10)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .onChange(of: formData.locationEnd) { _, value in
                        addressInputDidChange(value, target: .destination)
                    }
                
                Menu {
                    Button {
                        selectedAddressIndex = nil
                        addressPickerTarget = .destination
                    } label: {
                        Label("选择客户常用地址", systemImage: "book.closed")
                    }
                    .disabled(formData.selectedCustomerUUID == nil)

                    Button {
                        currentLocationTarget = .destination
                        locationManager.requestCurrentLocation()
                    } label: {
                        Label("使用当前位置", systemImage: "location.fill")
                    }
                } label: {
                    Image(systemName: "book.closed")
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .accessibilityLabel("选择目的地地址")

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
            VStack(alignment: .leading, spacing: 8) {
                Label("航班信息", systemImage: "airplane")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                TextField("", text: $formData.flightInfo, prompt: Text("请输入航班号（如UA123）").foregroundStyle(.secondary))
                    .font(.system(size: 14))
                    .nativeIMEInput()
                    .padding(10)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                }
            }
            HStack(spacing: 12) {
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

            if let flightLookupError {
                Text(LocalizedStringKey(flightLookupError))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if !formData.flightDepartureTime.isEmpty {
                LabeledContent("起飞时间", value: formData.flightDepartureTime).font(.caption)
            }
            if !formData.flightEstimatedArrivalTime.isEmpty {
                LabeledContent("预计到达时间", value: formData.flightEstimatedArrivalTime).font(.caption)
            }
            if !formData.flightArrivalTerminal.isEmpty {
                LabeledContent("到达航站楼", value: formData.flightArrivalTerminal).font(.caption)
            }
            if !formData.flightBaggageCarousel.isEmpty {
                LabeledContent("行李转盘", value: formData.flightBaggageCarousel).font(.caption)
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
            let value = target == .start ? formData.locationStart : formData.locationEnd
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
        isLookingUpFlight = true
        Task {
            defer { isLookingUpFlight = false }
            do {
                let result = try await FlightAwareClient().lookup(
                    flightNumber: formData.flightInfo,
                    flightDate: formData.flightdate
                )
                formData.flightDepartureTime = result.departureTime ?? ""
                formData.flightEstimatedArrivalTime = result.estimatedArrivalTime ?? ""
                formData.flightArrivalTerminal = result.arrivalTerminal ?? ""
                formData.flightBaggageCarousel = result.baggageCarousel ?? ""
                if result.arrivalTerminal == nil && result.baggageCarousel == nil {
                    flightLookupError = "已查到航班，但接口暂未提供到达航站楼或行李转盘信息。"
                }
            } catch {
                flightLookupError = error.localizedDescription
            }
        }
    }
}

private enum AddressPickerTarget: String, Identifiable {
    case start
    case destination

    var id: String { rawValue }
    var title: String { self == .start ? "选择起始点" : "选择目的地" }
}


//// 模块 6 布局 行程费用信息
struct TripDeteilSectionMoney: View {
    @Binding var formData: NewTripFormModel
    // 1. 数据模型中声明一个真实的 Double 变量（例如：订单金额）
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("费用与备注", systemImage: "dollarsign.circle")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("行程费用")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("", value: $formData.TripPrice, format: .number, prompt: Text("请输入订单金额（元）").foregroundStyle(.secondary))
                    .font(.system(size: 14))
                    .padding(10)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .keyboardType(.decimalPad)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("备注")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $formData.TripMemo)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 96)
                    .nativeIMEInput()
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

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24)

                    Text("行程状态")
                        .font(.subheadline)

                    Spacer()

                    Text("待执行")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.orange.opacity(0.12), in: Capsule())
                }
                .padding(.vertical, 4)

                Divider()
                    .padding(.vertical, 12)

                VStack(alignment: .leading, spacing: 10) {
                    Label("结算状态", systemImage: "banknote")
                        .font(.subheadline)

                    Picker("结算状态", selection: $formData.isPaid) {
                        Text("未结款").tag(false)
                        Text("已结清").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("结算状态")
                }
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
                    Text("默认：接载日期前一天的同一时间")
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
