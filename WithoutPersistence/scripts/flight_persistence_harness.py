"""Extract local flight selection actions; inject persistence and time-zone boundaries."""
from flight_editor_harness import block


def generate(root):
    source = (root/'Views/WishlistView.swift').read_text()
    output = '''import Foundation
@MainActor final class FlightPersistenceFixture {
    let persist: () throws -> Void
    init(_ persist: @escaping () throws -> Void) { self.persist = persist }
    func save() throws { try persist() }
}
'''
    for view, name in [('TripManagementCard','FlightCardPersistenceHarness'), ('TripBrowseView','FlightDetailPersistenceHarness')]:
        section = source[source.index('private struct '+view+':'):]
        methods = block(section,'private func selectFlight(_ result:')
        if 'saveChanges()' in methods: methods += '\n'+block(section,'private func saveChanges()')
        methods += '\n'+block(section,'private var savedFlightDisplayContext:')
        methods = methods.replace('        Task {','        zoneTask = Task {',1).replace('FlightTimeZoneResolver','FlightDisplayZoneFixture')
        output += '@MainActor final class '+name+' {\n'+'''
    let booking: TripBookingRecord
    let modelContext: FlightPersistenceFixture
    var flightLookupResult: VariFlightLookupResult?
    var flightLookupError: String?
    var departureTimeZoneLabel = ""
    var arrivalTimeZoneLabel = ""
    var showsFlightActions = true
    var zoneTask: Task<Void, Never>?
    init(booking: TripBookingRecord, persist: @escaping () throws -> Void) {
        self.booking = booking
        modelContext = FlightPersistenceFixture(persist)
    }
'''+methods+'\n}\n'
    return output
