"""Extract settlement form actions, replacing only SwiftUI property storage and dismissal."""
from flight_editor_harness import block


def generate(root):
    source = (root / 'Views/WishlistView.swift').read_text()
    source = source[source.index('private struct FinancialSettlementView:'):]
    methods = '\n'.join(block(source, marker) for marker in [
        'private func setAmountValidity(', 'private func saveSettlement('
    ])
    return '''import Foundation
import SwiftData
@MainActor final class SettlementFormHarness {
    let booking: TripBookingRecord
    let modelContext: ModelContext
    var tripFare: Double
    var tip: Double
    var expenseAdjustments: [TripExpenseAdjustment]
    var invalidAmountFields: Set<String> = []
    var errorMessage: String?
    var dismissed = false
    init(booking: TripBookingRecord, context: ModelContext) {
        self.booking = booking
        self.modelContext = context
        self.tripFare = booking.price
        self.tip = booking.tip
        self.expenseAdjustments = booking.expenseAdjustments
    }
    func dismiss() { dismissed = true }
''' + methods + '\n}\n'
