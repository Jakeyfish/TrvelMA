"""Extract editable flight methods for deterministic delayed-response tests.

Only auth, provider and time-zone boundaries are replaced in temporary copies.
SwiftUI property storage is represented by plain properties; rendering is not tested.
"""

def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        if source[end] == '{': depth += 1
        elif source[end] == '}': depth -= 1
        end += 1
    return source[start:end].replace('private func ', 'func ').replace('private var ', 'var ')


def generate(root):
    common = '''
    let auth = FlightRaceAuth()
    var flightLookupTask: Task<Void, Never>?
    var flightTimeZoneTask: Task<Void, Never>?
    var flightLookupResult: VariFlightLookupResult?
    var flightLookupError: String?
    var flightCandidates: [VariFlightLookupResult] = []
    var isChoosingFlight = false
    var isLookingUpFlight = false
    var departureTimeZoneLabel = ""
    var arrivalTimeZoneLabel = ""
'''
    output = '''import Foundation
@MainActor final class FlightRaceAuth {
    var isCloudAccount = true
    var canQueryFlights: Bool { isCloudAccount }
    var cloudAccessToken: String? = "fixture-only"
    func refreshCloudAccessToken() async -> String? { cloudAccessToken }
}
@MainActor struct FlightRaceClient {
    static var handler: ((String) async throws -> [VariFlightLookupResult])?
    func lookupCandidatesForTrip(flightNumber: String, flightDate: Date, serviceType: String, locationStart: String, locationEnd: String, cloudAccessToken: String?, forceRefresh: Bool = false) async throws -> [VariFlightLookupResult] {
        guard let handler = Self.handler else { throw URLError(.notConnectedToInternet) }
        return try await handler(flightNumber)
    }
    static func requiresExplicitFlightChoice(serviceType: String, locationStart: String, locationEnd: String) -> Bool { false }
}
@MainActor enum FlightRaceTimeZone {
    static var handler: ((String?) async -> String?)?
    static func label(for airport: String?, date: Date) async -> String? {
        await handler?(airport) ?? "Fixture zone"
    }
}
@MainActor protocol FlightRaceHarness: AnyObject {
    var flightLookupTask: Task<Void, Never>? { get }
    var flightLookupResult: VariFlightLookupResult? { get }
    var flightLookupError: String? { get }
    var flightCandidates: [VariFlightLookupResult] { get }
    var isLookingUpFlight: Bool { get }
    var savedFlightNumber: String? { get }
    func changeNumber(_ number: String)
    func lookupFlight()
    func invalidateFlightSelection()
}
'''
    for cloud, filename in [(True, 'CloudTripDirectoryView.swift'), (False, 'NewTripFormModel.swift')]:
        source = (root / 'Views/Trips' / filename).read_text()
        if cloud: source = source[source.index('private struct CloudTripEditor'):]
        methods = '\n'.join(block(source, marker) for marker in [
            'private var flightLookupContextKey:', 'private func lookupFlight()',
            'private func invalidateFlightSelection()', 'private func selectFlight(_ result:'
        ])
        methods = methods.replace('VariFlightClient()', 'FlightRaceClient()').replace('VariFlightClient.', 'FlightRaceClient.').replace('FlightTimeZoneResolver', 'FlightRaceTimeZone')
        if cloud:
            fields = '''
    var flightNumber = "UA1"
    var flightDate = Date(timeIntervalSince1970: 1700000000)
    var serviceType = "包车"
    var start = "Home"
    var destination = "Office"
    var departureTime = ""
    var estimatedArrivalTime = ""
    var terminal = ""
    var baggageCarousel = ""
    var flightSelectionSnapshot: SavedFlightSelection?
    var didClearFlightSelection = false
    var savedFlightNumber: String? { flightSelectionSnapshot?.flightNumber }
    func changeNumber(_ number: String) { flightNumber = number; invalidateFlightSelection() }
'''
        else:
            fields = '''
    var formData: NewTripFormModel = {
        var value = NewTripFormModel()
        value.flightInfo = "UA1"
        value.flightdate = Date(timeIntervalSince1970: 1700000000)
        value.serviceType = "包车"
        value.locationStart = "Home"
        value.locationEnd = "Office"
        return value
    }()
    var savedFlightNumber: String? {
        guard let data = formData.flightSelectionSnapshotJSON.data(using: .utf8) else { return nil }
        return (try? JSONDecoder().decode(SavedFlightSelection.self, from: data))?.flightNumber
    }
    func changeNumber(_ number: String) { formData.flightInfo = number; invalidateFlightSelection() }
'''
        output += '@MainActor final class ' + ('CloudFlightRaceHarness' if cloud else 'LocalFlightRaceHarness') + ': FlightRaceHarness {\n' + common + fields + methods + '\n}\n'
    output += """
@MainActor struct FlightReadOnlyTrip {
    var flightInfo = "UA1"
    var flightDate = "2026-10-24T00:00:00Z"
    var serviceType = "包车"
    var locationStart = "Home"
    var locationEnd = "Office"
}
@MainActor final class FlightSaveFixture {
    var errorMessage: String?
    var callCount = 0
    var started: (() -> Void)?
    var continuation: CheckedContinuation<Bool, Never>?
    func updateStatus(for trip: FlightReadOnlyTrip, flightSelectionSnapshot: SavedFlightSelection, using auth: FlightRaceAuth) async -> Bool {
        callCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            started?()
        }
    }
    func finish(saved: Bool) {
        errorMessage = saved ? nil : "Fixture save failed"
        continuation?.resume(returning: saved)
        continuation = nil
    }
}
@MainActor protocol FlightReadOnlyHarness: AnyObject {
    var savedFlightDisplayContext: Int { get set }
    var flightLookupResult: VariFlightLookupResult? { get set }
    var directory: FlightSaveFixture { get }
    var lookupTask: Task<Void, Never>? { get }
    var selectionTask: Task<Void, Never>? { get }
    var isLookingUpFlight: Bool { get }
    var isChoosingFlight: Bool { get }
    var flightLookupError: String? { get }
    func lookupFlight(forceRefresh: Bool)
}
"""
    source = (root / 'Views/Trips/CloudTripDirectoryView.swift').read_text()
    for kind in ['ManagementCard', 'DetailView']:
        section = source[source.index('private struct CloudTrip' + kind):]
        lookup = block(section, 'private func lookupFlight(forceRefresh:')
        selection = block(section, 'private func selectFlight(_ result:')
        # Retain task handles for deterministic waiting, without changing task bodies.
        lookup = lookup.replace('        Task {', '        lookupTask = Task {', 1)
        selection = selection.replace('        Task {', '        selectionTask = Task {', 1)
        methods = (lookup + '\n' + selection).replace('VariFlightClient()', 'FlightRaceClient()').replace('VariFlightClient.', 'FlightRaceClient.').replace('FlightTimeZoneResolver', 'FlightRaceTimeZone').replace('trip.flightDate.cloudDate', 'Date(timeIntervalSince1970: 1700000000)')
        output += '@MainActor final class Flight' + kind + 'Harness: FlightReadOnlyHarness {\n' + common + """
    var savedFlightDisplayContext = 0
    let directory = FlightSaveFixture()
    let trip = FlightReadOnlyTrip()
    let locale = Locale(identifier: "en_US")
    var lookupTask: Task<Void, Never>?
    var selectionTask: Task<Void, Never>?
""" + methods + '\n}\n'
    return output
