"""Extract production saved-snapshot refresh actions; replace view storage and time-zone lookup."""
from flight_editor_harness import block


def generate(root):
    output = '''import Foundation
@MainActor enum FlightDisplayZoneFixture {
    static var handler: ((String?) async -> String?)?
    static func label(for airport: String?, date: Date) async -> String? {
        await handler?(airport) ?? "Fixture zone"
    }
}
@MainActor protocol SavedFlightDisplayHarness: AnyObject {
    var flightLookupResult: VariFlightLookupResult? { get set }
    var flightLookupError: String? { get set }
    var flightCandidates: [VariFlightLookupResult] { get set }
    var isChoosingFlight: Bool { get set }
    var isFlightExpanded: Bool { get set }
    var departureTimeZoneLabel: String { get }
    var refreshTask: Task<Void, Never>? { get }
    func setSnapshot(_ snapshot: SavedFlightSelection?)
    func setFlightNumber(_ number: String)
    func refreshSavedFlightDisplay()
}
@MainActor struct DisplayTripFixture {
    let id = "fixture-trip"
    var flightInfo = "UA1743"
    var flightDate = "2026-10-24T00:00:00Z"
    var serviceType = "接机"
    var locationStart = "LAX Airport"
    var locationEnd = "Hotel"
    var flightSelectionSnapshot: SavedFlightSelection?
    var isCompleted = false
    var isCancelled = false
}
@MainActor final class DisplayDirectoryFixture {
    var trips: [DisplayTripFixture] = []
}
'''
    common = '''
    var flightLookupResult: VariFlightLookupResult?
    var flightLookupError: String?
    var flightCandidates: [VariFlightLookupResult] = []
    var isChoosingFlight = false
    var isFlightExpanded = true
    var departureTimeZoneLabel = ""
    var arrivalTimeZoneLabel = ""
    var refreshTask: Task<Void, Never>?
'''
    for cloud, filename, names in [
        (False, 'WishlistView.swift', ['TripManagementCard', 'TripBrowseView']),
        (True, 'Trips/CloudTripDirectoryView.swift', ['CloudTripManagementCard', 'CloudTripDetailView'])
    ]:
        source = (root/'Views'/filename).read_text()
        for name in names:
            section = source[source.index('private struct '+name+':'):]
            methods = block(section, 'private var savedFlightDisplayContext:') + '\n' + block(section, 'private func refreshSavedFlightDisplay()')
            methods = methods.replace('        Task {', '        refreshTask = Task {', 1).replace('FlightTimeZoneResolver', 'FlightDisplayZoneFixture').replace('trip.flightDate.cloudDate', 'ISO8601DateFormatter().date(from: trip.flightDate)!')
            output += '@MainActor final class '+name+'DisplayHarness: SavedFlightDisplayHarness {\n'+common
            if cloud:
                if name.endswith('DetailView'):
                    output += '''
    let initialTrip = DisplayTripFixture()
    let directory = DisplayDirectoryFixture()
''' + block(section, 'private var trip:').replace('CloudOnlineRepository.CloudTripRecord', 'DisplayTripFixture') + '''
    func setSnapshot(_ snapshot: SavedFlightSelection?) {
        var latest = directory.trips.first ?? initialTrip
        latest.flightSelectionSnapshot = snapshot
        directory.trips = [latest]
    }
    func setFlightNumber(_ number: String) {
        var latest = directory.trips.first ?? initialTrip
        latest.flightInfo = number
        directory.trips = [latest]
    }
''' + block(section, 'private var isCompleted:') + '\n' + block(section, 'private var isCancelled:') + '\n'
                else:
                    output += '''
    var trip = DisplayTripFixture()
    var showsFlightActions = true
    func setSnapshot(_ snapshot: SavedFlightSelection?) { trip.flightSelectionSnapshot = snapshot }
    func setFlightNumber(_ number: String) { trip.flightInfo = number }
'''
            else:
                output += '''
    let booking: TripBookingRecord = {
        var form = NewTripFormModel()
        form.flightInfo = "UA1743"
        form.flightdate = Date(timeIntervalSince1970: 1792800000)
        form.serviceType = "接机"
        form.locationStart = "LAX Airport"
        form.locationEnd = "Hotel"
        return TripBookingRecord(form: form)
    }()
    var showsFlightActions = true
    func setSnapshot(_ snapshot: SavedFlightSelection?) {
        booking.flightSelectionSnapshotJSON = snapshot.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding:$0,as:UTF8.self) } ?? ""
    }
    func setFlightNumber(_ number: String) { booking.flightInfo = number }
'''
            output += methods+'\n}\n'
    return output
