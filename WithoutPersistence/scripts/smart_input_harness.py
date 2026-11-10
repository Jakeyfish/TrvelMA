"""Exercise the actual cloud editor mapping with in-memory field boundaries."""
from flight_editor_harness import block
import re

def generate(root):
    source = (root / 'Views/Trips/CloudTripDirectoryView.swift').read_text()
    section = source[source.index('private struct CloudTripEditor:'):]
    local_source = (root / 'Views/Trips/NewTripFormModel.swift').read_text()
    local_section = local_source[local_source.index('struct QuickInputSection:'):]
    local_action = block(local_section, 'SmartTripInput(text: $formData.quickInputText)')
    local_action = local_action.split('result in', 1)[1].rsplit('}', 1)[0]
    local_harness = '''
@MainActor final class LocalSmartInputHarness {
    let context: ModelContext
    var formData = NewTripFormModel()
    init(context: ModelContext) { self.context = context }
    func applyRecognizedOrder(_ result: RecognizedPickupOrder) {
''' + local_action + '''
    }
}
'''
    method = block(section, 'private func applyRecognizedOrder(').replace('private func', 'func', 1)
    method = method.replace('agencyCode: matches.count == 1 ? matches.first?.agencyCode : nil)', 'agencyCode: matches.count == 1 ? matches.first?.agencyCode : nil, now: recognitionNow)')
    reminder_method = block(section, 'private func updateSecondReminderDefault(')
    reminder_method = reminder_method.replace('SmartPickupReminderPlan.dates(before: appointment)', 'SmartPickupReminderPlan.dates(before: appointment, now: recognitionNow)')
    settlement_route = block(section, 'if settlementOnly, let trip {')
    route_harness = '''
@MainActor final class CloudSettlementRouteHarness {
    struct Existing { let id: String }
    struct Expense { var remoteID: String?; var title: String; var amount: String; var isAddition: Bool }
    final class Directory {
        var succeeds = true, calls = 0
        var savedID = "", savedFare = 0.0, savedTip = 0.0
        var savedMarkPaid = true
        var savedExpenses: [[String: Any]] = []
        func settle(id: String, fare: Double, tip: Double, expenses: [[String: Any]], markPaid: Bool = true, using auth: Int) async -> Bool {
            calls += 1; savedMarkPaid = markPaid; savedID = id; savedFare = fare; savedTip = tip; savedExpenses = expenses
            return succeeds
        }
    }
    let directory = Directory(), auth = 0
    var trip: Existing? = .init(id: "00000000-0000-0000-0000-000000000002")
    var settlementOnly = true, dismissed = false
    var price = "90", tip = "5"
    var expenses = [Expense(remoteID:nil,title:"Parking",amount:"2",isAddition:false)]
    var reachedFullSave = false
    func dismiss() { dismissed = true }
    func save(markPaid: Bool = true) async {
''' + settlement_route + '''
        reachedFullSave = true
    }
}
'''
    identity = re.search(r'let id = (.+)', block(section, 'private func save(markPaid:')).group(1)
    identity_harness = '''
@MainActor final class CloudDraftIdentityHarness {
    struct Existing { let id: String }
    var trip: Existing?
    var copyAsNew = false
    let draftID = UUID().uuidString.lowercased()
    func saveID() -> String { return ''' + identity + ''' }
}
'''
    return '''import Foundation
import SwiftData
@MainActor final class CloudSmartInputHarness {
    struct Agency { var name: String; var agencyCode: String }
    struct Directory { var agencies = [Agency(name: "途风", agencyCode: "TF")] }
    let recognitionNow = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
    var directory = Directory()
    var agencyName = "Other", agencyCode = "OTHER", agencyOrderNumber = "", customerID = "existing"
    var customerName = "Keep", customerContact = "", customerCount = "1", customerStuff = "0"
    var destination = "", memo = "Manual note", serviceType = "包车", orderSource = "普通客户"
    var appointmentDate = Date(), flightDate = Date(), appointmentTime = Date(timeIntervalSince1970: 1700000000)
    var flightNumber = "", start = "", price = "123", tip = "5"
    var reminderEnabled = false, hasSecondReminder = false
    var reminderDate = Date(), secondReminderDate = Date()
    var invalidations = 0
    func invalidateFlightSelection() { invalidations += 1 }
''' + method + '\n' + reminder_method + '\n}\n' + identity_harness + route_harness + local_harness
