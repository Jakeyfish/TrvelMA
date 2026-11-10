"""Extract production execution-state actions; inject only persistence and plain view storage."""
from flight_editor_harness import block


def generate(root):
    source = (root / 'Views/WishlistView.swift').read_text()
    listing = source[source.index('struct TripListDashboardView:'):]
    detail = source[source.index('private struct TripBrowseView:'):]
    card = source[source.index('private struct TripManagementCard:'):]
    common = '''
    let booking: TripBookingRecord
    let modelContext: ExecutionPersistenceFixture
    init(booking: TripBookingRecord, persist: @escaping () throws -> Void) {
        self.booking = booking
        self.modelContext = ExecutionPersistenceFixture(persist: persist)
    }
'''
    return '''import Foundation
@MainActor final class ExecutionPersistenceFixture {
    let persist: () throws -> Void
    init(persist: @escaping () throws -> Void) { self.persist = persist }
    func save() throws { try persist() }
}
@MainActor final class ListCompletionHarness {
    var completionBooking: TripBookingRecord?
    var completionErrorMessage: String?
''' + common + block(listing, 'private func requestCompletion(') + '''
}
@MainActor final class DetailCompletionHarness {
    var isShowingCompletionSettlementPrompt = false
    var errorMessage: String?
''' + common + block(detail, 'private func completeTrip()') + '\n' + block(detail, 'private func setExecutionState(') + '''
}
@MainActor final class CardCancellationHarness {
    var executionErrorMessage: String?
''' + common + block(card, 'private func setCancelled(') + '\n}\n'
