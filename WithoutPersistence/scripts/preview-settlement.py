#!/usr/bin/env python3
"""Build and launch isolated production settlement, nickname, or QR UI without cloud data.

No login, cloud repository or production data store is opened. Temporary copies only expose
FinancialSettlementView and omit the production @main entry point. No repository project edits.
"""
from pathlib import Path
import argparse, json, plistlib, subprocess, tempfile, uuid, sys
sys.dont_write_bytecode = True
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--screen", choices=["trip-contact", "customer", "settlement", "nickname", "qr", "flight", "completion", "completion-list", "flight-info", "flight-live-snapshot", "smart-input", "trip-address", "expense-items", "finance", "finance-flight"], default="settlement")
parser.add_argument("--input-file", type=Path, help="Optional local text fixture for the memory-only smart-input screen")
parser.add_argument("--live-address-lookup", action="store_true", help="Allow public MapKit queries in the isolated address preview")
parser.add_argument("--shared-address-field", action="store_true", help="Preview the shared cloud editor address component")
parser.add_argument("--no-launch", action="store_true", help="Build/install only; open the QA app manually")
parser.add_argument("--customer-baseline", action="store_true", help="Use committed customer navigation for before/after reproduction")
args = parser.parse_args()
bundle_id = 'com.trvelma.acceptance.' + {'trip-contact':'trip-contact-preview','customer':'customer-preview','settlement':'settlement-preview','nickname':'nickname-preview','qr':'qr-preview','flight':'flight-preview','completion':'completion-preview','completion-list':'completion-list-preview','flight-info':'flight-info-preview','flight-live-snapshot':'flight-live-snapshot-preview','smart-input':'smart-input-preview','trip-address':'trip-address-preview','finance-flight':'finance-flight-preview','finance':'finance-preview','expense-items':'expense-items-preview'}[args.screen]
display_name = {'trip-contact':'QA 行程联系','customer':'QA 客户编辑','settlement':'QA 结算预览','nickname':'QA 昵称预览','qr':'QA 二维码预览','flight':'QA 航段预览','completion':'QA 完成结算预览','completion-list':'QA 列表完成预览','flight-info':'QA 航站楼预览','flight-live-snapshot':'QA 同步快照预览','smart-input':'QA 途风识别预览','trip-address':'QA 地址键盘预览','finance-flight':'QA 财务航班快照','finance':'QA 财务预览','expense-items':'QA 费用项目预览'}[args.screen]

root = Path(__file__).resolve().parents[1] / 'Wishlist'
base = Path(tempfile.mkdtemp(prefix='trvelma-settlement-preview-'))
objects = {}

def obj(isa, **values):
    key = uuid.uuid4().hex[:24].upper()
    objects[key] = {'isa': isa, **values}
    return key

refs, builds = [], []
for path in sorted(root.rglob('*.swift')):
    if path.name.startswith('._'): continue
    if (args.screen == 'finance-flight' and path.name == 'WalletView.swift') or path.name in ['WishlistApp.swift', 'WishlistView.swift', 'BusinessCardView.swift'] or (args.screen in ['customer','trip-contact'] and path.name in ['AuthViewModel.swift', 'CloudCustomerDirectoryView.swift']) or (args.screen in ['smart-input','trip-address','finance'] and path.name in ['NewTripFormModel.swift','AuthViewModel.swift']):
        text = path.read_text()
        if args.screen == 'customer' and path.name == 'CloudCustomerDirectoryView.swift':
            if args.customer_baseline:
                text = subprocess.check_output(['git', 'show', 'HEAD:WithoutPersistence/Wishlist/Views/Customers/CloudCustomerDirectoryView.swift'], cwd=root.parent, text=True)
            text = text.replace('private struct CloudCustomerDetailView:', 'struct CloudCustomerDetailView:', 1)
            text = text.replace('await directory.reloadTrips(for: customer.id, using: auth)', '_ = customer.id // QA: no network, synthetic empty trip history', 1)
        elif path.name == 'WishlistApp.swift': text = text.replace('@main\n', '')
        elif path.name == 'WishlistView.swift':
            text = text.replace('private struct FinancialSettlementView:', 'struct FinancialSettlementView:', 1)
            text = text.replace('private struct ExpenseItemManagementView:', 'struct ExpenseItemManagementView:', 1)
            text = text.replace('private struct TripBrowseView:', 'struct TripBrowseView:', 1)
        elif path.name == 'WalletView.swift':
            text = text.replace('                        DisclosureGroup {', '                        DisclosureGroup(isExpanded: .constant(true)) {', 1)
        elif path.name == 'AuthViewModel.swift':
            text = text.replace('    init() {\n        restoreSession()\n    }', '    init() {} // Isolated preview: no credential/session restore', 1)
        elif path.name == 'NewTripFormModel.swift':
            text = text.replace('private struct TripReminderSection:', 'struct TripReminderSection:', 1)
            if args.screen == 'trip-address' and not args.live_address_lookup: text = text.replace('next.queryFragment = query', '_ = query // Isolated keyboard preview: no MapKit request', 1)
            text = text.replace('let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false', 'let granted = true // QA permission boundary; no OS prompt or notifications', 1)
        else:
            text = text.replace('private struct BusinessCardQR:', 'struct BusinessCardQR:', 1)
            text = text.replace('private struct BusinessCardQRRow:', 'struct BusinessCardQRRow:', 1)
        path = base / path.name
        path.write_text(text)
    ref = obj('PBXFileReference', lastKnownFileType='sourcecode.swift', path=str(path), sourceTree='<absolute>')
    refs.append(ref); builds.append(obj('PBXBuildFile', fileRef=ref))
entry = base / 'SettlementPreviewApp.swift'
entry.write_text('''import SwiftUI
import SwiftData
@main struct SettlementPreviewApp: App {
    let container: ModelContainer
    let booking: TripBookingRecord
    init() {
        let schema = Schema(AppDataSchema.modelTypes)
        container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        var form = NewTripFormModel()
        form.customerName = "QA · 隔离结算界面"
        form.locationStart = "Fixture start"
        form.locationEnd = "Fixture destination"
        form.TripPrice = 90
        booking = TripBookingRecord(form: form)
        booking.isCompleted = true
        booking.expenseAdjustments = [.init(isAddition: false, title: "Parking", amount: 10)]
        container.mainContext.insert(booking)
    }
    var body: some Scene {
        WindowGroup {
            NavigationStack { FinancialSettlementView(booking: booking) }
                .modelContainer(container)
        }
    }
}
''')
if args.screen == 'customer':
    entry.write_text('''import SwiftUI
import SwiftData
@main struct CustomerEditQAApp: App {
    @State private var auth = AuthViewModel()
    @State private var language = AppLanguageSettings()
    let customer = CloudOnlineRepository.CustomerRecord(id: "11111111-1111-4111-8111-111111111111", name: "QA Customer", email: "qa@example.invalid", avatarURL: "", source: "", type: 1, category: 1, travelAgencyCode: "", travelAgencyName: "", languagePreference: "zh-Hans", remark: "Isolated editing preview", contacts: [.init(id: "22222222-2222-4222-8222-222222222222", customerID: "11111111-1111-4111-8111-111111111111", label: "电话", contactType: "电话", value: "+1 555 000 0100", isDefault: true)], addresses: [])
    @State private var directory = CloudCustomerDirectoryModel()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List { NavigationLink("QA Customer") { CloudCustomerDetailView(customer: customer, directory: directory) } }
                    .navigationTitle("QA Customers")
            }.environment(auth).environment(language)
        }
    }
}
''')
if args.screen == 'trip-contact':
    text = entry.read_text().replace('NavigationStack { FinancialSettlementView(booking: booking) }', 'NavigationStack { TripListDashboardView() }.environment(AuthViewModel()).environment(AppLanguageSettings())')
    text = text.replace('booking.isCompleted = true', 'booking.isCompleted = false\n        booking.customerContact = "+1 (555) 000-0100"')
    entry.write_text(text)
if args.screen == 'finance':
    text = entry.read_text().replace('NavigationStack { FinancialSettlementView(booking: booking) }', 'WalletView().environment(AuthViewModel())')
    text = text.replace('booking.isCompleted = true', 'booking.ownerScope = DataOwnership.activeScope\n        booking.isCompleted = true')
    text = text.replace('form.customerName = "QA · 隔离结算界面"', 'form.customerName = "QA · 财务快照"')
    entry.write_text(text)
if args.screen == 'finance-flight':
    entry.write_text('''import SwiftUI
@main struct FinanceFlightQAApp: App {
    var body: some Scene {
        WindowGroup {
            FinancialTripSnapshotSheet(snapshot: FinancialTripSnapshotCollection(rows: [
                FinancialTripSnapshotRow(id: "qa-finance-flight", date: Date(), time: Date(),
                    guest: "QA · 航班快照", amount: "$100.00",
                    details: FinancialTripSnapshotRow.details(service: "接机", start: "LAX", stops: [], end: "QA Hotel",
                        flight: "BR15", completed: true, cancelled: false, paid: true, contact: "", passengers: "1", luggage: "0",
                        agency: "", order: "", memo: "合成资料 · 无云端写入"),
                    flightResult: VariFlightLookupResult(airlineName: "长荣航空股份有限公司", departureAirport: "TPE", arrivalAirport: "LAX",
                        departureTerminal: "2", arrivalTerminal: "TBIT", departureTime: "2026-11-16 13:50:00",
                        estimatedArrivalTime: "2026-11-16 16:35:00", baggageCarousel: nil, status: "落地"))
            ]))
            .environment(\.locale, Locale(identifier: "zh-Hans"))
        }
    }
}
''')
if args.screen == 'nickname':
    from flight_editor_harness import block
    source = (root / 'Views/BusinessCardView.swift').read_text()
    nickname_field = block(source, 'private var nicknameField:')
    text = entry.read_text().replace('NavigationStack { FinancialSettlementView(booking: booking) }', 'NicknamePreview()')
    text += """
struct NicknamePreview: View {
    private struct NicknameDraft { var nickname = "" }
    @State private var draft = NicknameDraft()
    private func localized(_ key: String) -> String { key }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("仅内存测试，不保存名片")
                    nicknameField
                    Text("读回：" + draft.nickname)
                }.padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("QA · 名片昵称")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("保存") {} } }
        }
    }
""" + nickname_field + "\n}\n"
    entry.write_text(text)
if args.screen == 'qr':
    text = entry.read_text().replace('NavigationStack { FinancialSettlementView(booking: booking) }', 'QRPreview()')
    text += """
import CoreImage
import UIKit
struct QRPreview: View {
    @State private var language = AppLanguageSettings()
    @State private var showRow = true
    @State private var item = BusinessCardQR(name: "QA 测试二维码", imageData: QRPreview.fixtureImage())
    static func fixtureImage() -> Data? {
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data("QA-ONLY-NO-PERSONAL-DATA".utf8), forKey: "inputMessage")
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cgImage).pngData()
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text("仅内存测试；二维码不含个人资料")
                    if showRow {
                        BusinessCardQRRow(item: $item, onDelete: { showRow = false }, onImageLoaded: { item.imageData = $0 })
                    }
                    Text("名称读回：" + item.name)
                }.padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("QA · 二维码")
            .navigationBarTitleDisplayMode(.inline)
        }.environment(language)
    }
}
"""
    entry.write_text(text)
if args.screen == 'flight':
    text = entry.read_text().replace('NavigationStack { FinancialSettlementView(booking: booking) }', 'FlightSelectionPreview()')
    text += """
struct FlightSelectionPreview: View {
    @State private var flightNumber = "UA1743"
    @State private var selection: VariFlightLookupResult?
    @State private var snapshotData: Data?
    @State private var status = "尚未保存测试快照"
    @State private var isChoosing = false
    private let flightDate = Date(timeIntervalSince1970: 1792886400)
    private let candidates = [
        VariFlightLookupResult(airlineName: "美国联合航空公司", departureAirport: "旧金山 SFO", arrivalAirport: "洛杉矶 LAX", departureTerminal: nil, arrivalTerminal: "7", departureTime: "14:00", estimatedArrivalTime: "15:30", baggageCarousel: nil),
        VariFlightLookupResult(airlineName: "美国联合航空公司", departureAirport: "乔治布什 IAH", arrivalAirport: "洛杉矶 LAX", departureTerminal: nil, arrivalTerminal: "7", departureTime: "16:30", estimatedArrivalTime: "18:07", baggageCarousel: nil)
    ]
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("固定 QA 航段，仅内存测试，不请求航班服务")
                    LabeledContent("航班号", value: flightNumber)
                    Button("选择航段") { isChoosing = true }
                }
                Section("当前显示") {
                    if let selection {
                        Text(selection.routeLabel)
                        Text((selection.departureTime ?? "") + " → " + (selection.estimatedArrivalTime ?? ""))
                    } else { Text("未选择航段") }
                    Text(status)
                }
                Section("快照验证") {
                    Button("清空当前显示，保留 JSON 快照") { selection = nil }
                    Button("从 JSON 快照读回") {
                        guard let snapshotData,
                              let snapshot = try? JSONDecoder().decode(SavedFlightSelection.self, from: snapshotData),
                              snapshot.matches(flightNumber: flightNumber, flightDate: flightDate) else {
                            selection = nil
                            status = "快照缺失或不匹配当前航班，未采用"
                            return
                        }
                        selection = snapshot.selected
                        status = "快照读回成功"
                    }
                    Button("改号为 UA9999 并清空显示") { flightNumber = "UA9999"; selection = nil }
                }
            }
            .navigationTitle("QA · 航段选择")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isChoosing) {
                FlightCandidatePicker(candidates: candidates) { candidate in
                    selection = candidate
                    snapshotData = try? JSONEncoder().encode(SavedFlightSelection(flightNumber: flightNumber, flightDate: flightDate, selected: candidate))
                    status = "测试快照已编码为 JSON"
                }
            }
        }
    }
}
"""
    entry.write_text(text)
if args.screen == 'completion':
    text = entry.read_text().replace('booking.isCompleted = true', 'booking.isCompleted = false')
    text = text.replace('NavigationStack { FinancialSettlementView(booking: booking) }', 'NavigationStack { TripBrowseView(booking: booking) }.environment(AuthViewModel())')
    entry.write_text(text)
if args.screen == 'completion-list':
    text = entry.read_text().replace('booking.isCompleted = true', 'booking.isCompleted = false')
    text = text.replace('NavigationStack { FinancialSettlementView(booking: booking) }',
                        'NavigationStack { TripListDashboardView() }.environment(AuthViewModel()).environment(AppLanguageSettings())')
    entry.write_text(text)
if args.screen == 'flight-info':
    text = entry.read_text().replace('NavigationStack { FinancialSettlementView(booking: booking) }', 'FlightInformationPreview()')
    text += """
struct FlightInformationPreview: View {
    @State private var result = FlightInformationPreview.fixture(terminals: true)
    @State private var status = "固定 QA 航段，未连接订单或航班服务"
    private let date = Date(timeIntervalSince1970: 1792886400)
    static func fixture(terminals: Bool) -> VariFlightLookupResult {
        VariFlightLookupResult(airlineName: "United", departureAirport: "乔治布什 IAH", arrivalAirport: "洛杉矶 LAX", departureTerminal: terminals ? "C" : nil, arrivalTerminal: terminals ? "7" : nil, departureTime: "16:30", estimatedArrivalTime: "18:07", baggageCarousel: nil)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Text(status).font(.caption)
                    FlightInformationPanel(flightNumber: "UA1743", flightDate: date, result: result, isLoading: false, error: nil, departureFallback: "", arrivalFallback: "", departureTimeZone: "GMT−5", arrivalTimeZone: "GMT−7")
                        .padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
                    Button("切换到未提供航站楼") { result = Self.fixture(terminals: false) }
                    Button("保存并从 JSON 读回航站楼") {
                        let snapshot = SavedFlightSelection(flightNumber: "UA1743", flightDate: date, selected: Self.fixture(terminals: true))
                        if let data = try? JSONEncoder().encode(snapshot),
                           let read = try? JSONDecoder().decode(SavedFlightSelection.self, from: data) {
                            result = read.selected
                            status = "航站楼快照读回成功"
                        }
                    }
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("QA · 航站楼显示")
            .navigationBarTitleDisplayMode(.inline)
        }.environment(\.locale, Locale(identifier: "zh_Hans_CN"))
    }
}
"""
    entry.write_text(text)
if args.screen == 'flight-live-snapshot':
    text = entry.read_text().replace('booking.isCompleted = true', 'booking.isCompleted = false')
    text = text.replace('container.mainContext.insert(booking)', """booking.flightInfo = "UA1743"
        booking.locationStart = "LAX Airport"
        let initial = SavedFlightSelection(flightNumber: booking.flightInfo, flightDate: booking.flightDate,
            selected: VariFlightLookupResult(airlineName: "Fixture", departureAirport: "IAH", arrivalAirport: "LAX", departureTerminal: nil, arrivalTerminal: nil, departureTime: "16:30", estimatedArrivalTime: "18:07", baggageCarousel: nil))
        booking.flightSelectionSnapshotJSON = String(decoding: try! JSONEncoder().encode(initial), as: UTF8.self)
        container.mainContext.insert(booking)""")
    text = text.replace('NavigationStack { FinancialSettlementView(booking: booking) }',
                        'LiveSnapshotPreview(booking: booking).environment(AuthViewModel()).environment(AppLanguageSettings())')
    text += """
struct LiveSnapshotPreview: View {
    @Bindable var booking: TripBookingRecord
    var body: some View {
        NavigationStack {
            VStack {
                Text("仅内存模拟远端快照，不连接账号或航班服务").font(.caption)
                HStack {
                    Button("模拟同步 C / T7") {
                        let saved = SavedFlightSelection(flightNumber: "UA1743", flightDate: booking.flightDate,
                            selected: VariFlightLookupResult(airlineName: "Fixture", departureAirport: "IAH", arrivalAirport: "LAX", departureTerminal: "C", arrivalTerminal: "T7", departureTime: "16:30", estimatedArrivalTime: "18:07", baggageCarousel: nil))
                        booking.flightSelectionSnapshotJSON = String(decoding: try! JSONEncoder().encode(saved), as: UTF8.self)
                    }
                    Button("模拟移除快照") { booking.flightSelectionSnapshotJSON = "" }
                }.buttonStyle(.bordered)
                TripListDashboardView()
            }
        }
    }
}
"""
    entry.write_text(text)
if args.screen == 'expense-items':
    entry.write_text('''import SwiftUI
import SwiftData
@main struct ExpenseItemsAcceptanceApp: App {
    let container: ModelContainer
    let booking: TripBookingRecord
    init() {
        DataOwnership.activateLocal(scope: "acceptance-expense-items")
        let schema = Schema(AppDataSchema.modelTypes)
        container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        var form = NewTripFormModel()
        form.customerName = "QA Settlement"
        form.TripPrice = 90
        booking = TripBookingRecord(form: form)
        booking.isCompleted = true
        container.mainContext.insert(booking)
        if UserDefaults.standard.object(forKey: "financial.expenseItemNames.v1") == nil {
            UserDefaults.standard.set(try! JSONEncoder().encode(["QA Parking", "QA Toll"]), forKey: "financial.expenseItemNames.v1")
        }
    }
    var body: some Scene { WindowGroup { ExpenseItemsAcceptanceView(booking: booking).modelContainer(container) } }
}
struct ExpenseItemsAcceptanceView: View {
    let booking: TripBookingRecord
    @State private var settlementShowing = false
    @State private var showing = true
    @State private var saved = ""
    private func readback() {
        saved = (try? JSONDecoder().decode([String].self, from: UserDefaults.standard.data(forKey: "financial.expenseItemNames.v1") ?? Data()).joined(separator: " | ")) ?? "Unreadable"
    }
    var body: some View {
        VStack(spacing: 20) {
            Text("QA 独立费用目录，不连接账号")
            Text("保存读回：" + saved)
            Button("打开费用管理") { showing = true }
            Button("打开隔离结算") { settlementShowing = true }
        }
        .onAppear { readback() }
        .sheet(isPresented: $showing, onDismiss: { readback() }) { ExpenseItemManagementView() }
        .sheet(isPresented: $settlementShowing) { NavigationStack { FinancialSettlementView(booking: booking) } }
    }
}
''')
if args.screen == 'trip-address':
    entry.write_text('''import SwiftUI
import SwiftData
@main struct AddressAcceptanceApp: App {
    let container: ModelContainer = {
        DataOwnership.activateLocal(scope: "acceptance-address-keyboard")
        let schema = Schema(AppDataSchema.modelTypes)
        return try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
    }()
    var body: some Scene { WindowGroup { AddressAcceptanceView().modelContainer(container) } }
}
struct AddressAcceptanceView: View {
    @StateObject private var searcher = AddressAutocompleteSearcher()
    @State private var auth = AuthViewModel()
    @State private var form: NewTripFormModel = {
        var value = NewTripFormModel()
        value.locationStart = "QA start address"
        value.locationStops = ["QA stop address"]
        value.locationEnd = "QA destination address"
        return value
    }()
    var body: some View {
        NavigationStack {
            VStack {
                Text("地址建议查询：" + searcher.searchQuery + " · 候选：" + String(searcher.completions.count)).font(.caption)
                ScrollView { TripDeteilSection(formData: $form, searcher: searcher) }
            }
                .navigationTitle("QA 地址键盘")
                .navigationBarTitleDisplayMode(.inline)
                .environment(auth)
        }
    }
}
''')
if args.screen == 'trip-address' and args.shared_address_field:
    text = entry.read_text().replace('@State private var auth = AuthViewModel()', '@State private var auth = AuthViewModel()\n    @State private var selectedAddressField = 0')
    text = text.replace('ScrollView { TripDeteilSection(formData: $form, searcher: searcher) }', '''ScrollView {
                    VStack(spacing: 20) {
                        AddressSuggestionField(text: $form.locationStart, searcher: searcher, placeholder: "QA 起始点", isActive: selectedAddressField == 0, onFocus: { selectedAddressField = 0 }, onSelect: { form.locationStart = $0 })
                        AddressSuggestionField(text: $form.locationStops[0], searcher: searcher, placeholder: "QA 停靠点", isActive: selectedAddressField == 1, onFocus: { selectedAddressField = 1 }, onSelect: { form.locationStops[0] = $0 })
                        AddressSuggestionField(text: $form.locationEnd, searcher: searcher, placeholder: "QA 目的地", isActive: selectedAddressField == 2, onFocus: { selectedAddressField = 2 }, onSelect: { form.locationEnd = $0 })
                    }.padding()
                }''')
    entry.write_text(text)
if args.screen == 'trip-address' and args.live_address_lookup:
    entry.write_text(entry.read_text().replace('QA start address', 'LAX').replace('QA stop address', 'Pasadena').replace('QA destination address', 'Los Angeles'))
if args.screen == 'trip-address':
    entry.write_text(entry.read_text().replace('ScrollView {', 'AddressSuggestionScrollView {'))
if args.screen == 'smart-input':
    entry.write_text('import SwiftUI\nimport SwiftData\n@main struct SmartInputAcceptanceApp: App {\n    let container: ModelContainer\n    init() {\n        DataOwnership.activateLocal(scope: "acceptance-smart-input")\n        let schema = Schema(AppDataSchema.modelTypes)\n        container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])\n    }\n    var body: some Scene { WindowGroup { SmartInputAcceptanceView().modelContainer(container) } }\n}\nstruct SmartInputAcceptanceView: View {\n    @State private var form: NewTripFormModel = {\n        var value = NewTripFormModel()\n        value.quickInputText = "订单号：C-1234567-US\\n接机日期：11/25  航班号：JX2，抵达机场：LAX\\n接机时间：预计19:00 到达\\n类型：接机\\n客人地址：Pasadena Hotel & Pool 住址：928 E Colorado Blvd #101, Pasadena, CA 91106美國\\n联络人：QA GUEST（3人）\\n联络电话：886-900000001（台湾）\\n人数：3人，5件行李"\n        return value\n    }()\n    var body: some View {\n        NavigationStack {\n            ScrollView {\n                VStack(alignment: .leading, spacing: 16) {\n                    Text("隔离草稿，不保存、不连接云端").font(.caption)\n                    QuickInputSection(formData: $form)\n                    Text("来源：\\(form.orderSource) / \\(form.travelAgencyName)")\n                    Text("联系人：\\(form.customerName)")\n                    Text("人数：\\(form.customerCount) · 行李：\\(form.customerStuff)")\n                    Text("航班：\\(form.flightInfo) · 起点：\\(form.locationStart)")\n                    Text("目的地：\\(form.locationEnd)")\n                    Text(form.TripMemo)\n                }.padding()\n            }.navigationTitle("QA 途风识别")\n        }\n    }\n}\n')
if args.screen == 'smart-input':
    code = entry.read_text().replace('                    QuickInputSection(formData: $form)', '                    QuickInputSection(formData: $form)\n                    OrderSourceSection(formData: $form)\n                    if form.orderSource == "旅行社订单" { TravelAgencyTripSection(formData: $form) }\n                    TripReminderSection(formData: $form)\n                    Text("接客时间：\\(form.appointmentTime.formatted(date: .numeric, time: .shortened))")\n                    Text("两条提醒：\\(form.reminderEnabled && form.hasSecondReminder ? "已开启" : "未开启")")')
    entry.write_text(code)
if args.screen == 'smart-input':
    marker = '        container = try! ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])\n'
    fixture = '        let agency = TravelAgency(agencyCode: "QA TF0001", name: "途风旅行", contactPerson: "QA Agency Desk", phone: "+1 5550000100")\n        agency.ownerScope = DataOwnership.activeScope\n        container.mainContext.insert(agency)\n        try! container.mainContext.save()\n'
    entry.write_text(entry.read_text().replace(marker, marker + fixture, 1))

if args.screen == 'smart-input' and args.input_file:
    fixture = args.input_file.read_text()
    lines = entry.read_text().splitlines()
    lines = [('        value.quickInputText = ' + json.dumps(fixture, ensure_ascii=False)) if 'value.quickInputText = ' in line else line for line in lines]
    entry.write_text('\n'.join(lines) + '\n')
ref = obj('PBXFileReference', lastKnownFileType='sourcecode.swift', path=str(entry), sourceTree='<absolute>')
refs.append(ref); builds.append(obj('PBXBuildFile', fileRef=ref))
product = obj('PBXFileReference', explicitFileType='wrapper.application', path='SettlementPreview.app', sourceTree='BUILT_PRODUCTS_DIR')
products = obj('PBXGroup', children=[product], name='Products', sourceTree='<group>')
group = obj('PBXGroup', children=refs+[products], sourceTree='<group>')
sources = obj('PBXSourcesBuildPhase', buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)
frameworks = obj('PBXFrameworksBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
resources = obj('PBXResourcesBuildPhase', buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
settings = {'PRODUCT_NAME':'SettlementPreview', 'PRODUCT_BUNDLE_IDENTIFIER':bundle_id, 'SDKROOT':'iphonesimulator', 'SUPPORTED_PLATFORMS':'iphonesimulator', 'IPHONEOS_DEPLOYMENT_TARGET':'26.0', 'SWIFT_VERSION':'5.0', 'SWIFT_APPROACHABLE_CONCURRENCY':'YES', 'SWIFT_DEFAULT_ACTOR_ISOLATION':'MainActor', 'SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY':'YES', 'GENERATE_INFOPLIST_FILE':'YES', 'INFOPLIST_KEY_UILaunchScreen_Generation':'YES', 'INFOPLIST_KEY_UIApplicationSceneManifest_Generation':'YES', 'INFOPLIST_KEY_CFBundleDisplayName':display_name, 'CODE_SIGNING_ALLOWED':'NO', 'TARGETED_DEVICE_FAMILY':'1,2', 'ONLY_ACTIVE_ARCH':'YES'}
conf = obj('XCBuildConfiguration', name='Debug', buildSettings=settings)
configs = obj('XCConfigurationList', buildConfigurations=[conf], defaultConfigurationIsVisible=0, defaultConfigurationName='Debug')
target = obj('PBXNativeTarget', name='SettlementPreview', productName='SettlementPreview', productReference=product, productType='com.apple.product-type.application', buildConfigurationList=configs, buildPhases=[sources,frameworks,resources], buildRules=[], dependencies=[])
pc = obj('XCBuildConfiguration', name='Debug', buildSettings={})
pcl = obj('XCConfigurationList', buildConfigurations=[pc], defaultConfigurationIsVisible=0, defaultConfigurationName='Debug')
project = obj('PBXProject', attributes={'LastUpgradeCheck':'2600'}, buildConfigurationList=pcl, compatibilityVersion='Xcode 14.0', developmentRegion='en', knownRegions=['en','Base'], mainGroup=group, productRefGroup=products, projectDirPath='', projectRoot='', targets=[target])
proj = base / 'SettlementPreview.xcodeproj'; proj.mkdir()
(proj/'project.pbxproj').write_bytes(plistlib.dumps({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project}))
devices = json.loads(subprocess.check_output(['xcrun','simctl','list','devices','booted','--json']))['devices']
booted = [d for runtime, entries in devices.items() if '.iOS-' in runtime for d in entries if d['state']=='Booted']
if not booted: raise SystemExit('Boot an iOS simulator first.')
device = booted[0]['udid']
print('Isolated UI artifacts:', base, flush=True)
with (base/'build.log').open('w') as output:
    result = subprocess.run(['xcodebuild','-project',str(proj),'-target','SettlementPreview','-configuration','Debug','-sdk','iphonesimulator','-arch','arm64','CONFIGURATION_BUILD_DIR='+str(base/'products'),'build'], stdout=output, stderr=subprocess.STDOUT)
if result.returncode:
    print('\n'.join(line for line in (base/'build.log').read_text().splitlines() if 'error:' in line))
    raise SystemExit(result.returncode)
subprocess.run(['xcrun','simctl','install',device,str(base/'products/SettlementPreview.app')],check=True)
if not args.no_launch: subprocess.run(['xcrun','simctl','launch',device,bundle_id],check=True)
print(('Launched isolated QA expense-items preview; QA app defaults persist for read-back.' if args.screen == 'expense-items' else 'Launched memory-only QA ' + args.screen + ' preview. Relaunch resets the fixture.'), flush=True)
