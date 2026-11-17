import Foundation
import MapKit

struct NavigationPoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    var isValid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }
    var queryValue: String { "\(latitude),\(longitude)" }
    static func parse(_ text: String) -> Self? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let latitude = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let longitude = Double(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        let point = Self(latitude: latitude, longitude: longitude)
        return point.isValid ? point : nil
    }
}

/// A bounded, account-scoped cache of locations explicitly selected by the user.
/// A cache miss is not permission to guess a destination from a place-name search.
@MainActor enum NavigationDestinationStore {
    private struct Entry: Codable { let point: NavigationPoint; let savedAt: Date }
    private static var generations: [String: Int] = [:]
    private static var pendingSelections: [String: UUID] = [:]
    private static func key(_ scope: String) -> String { "navigation.selectedLocations.v1.\(scope)" }
    static func addressKey(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private static func entries(_ scope: String) -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: key(scope)) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }
    static func point(for address: String, scope: String = DataOwnership.activeScope) -> NavigationPoint? {
        guard let entry = entries(scope)[addressKey(address)], entry.point.isValid,
              Date.now.timeIntervalSince(entry.savedAt) < 30 * 86400 else { return nil }
        return entry.point
    }
    static func remember(_ point: NavigationPoint, for address: String, scope: String = DataOwnership.activeScope) {
        guard point.isValid, !addressKey(address).isEmpty else { return }
        var values = entries(scope)
        values[addressKey(address)] = Entry(point: point, savedAt: .now)
        if values.count > 200 {
            values = Dictionary(uniqueKeysWithValues: values.sorted { $0.value.savedAt > $1.value.savedAt }.prefix(200).map { ($0.key, $0.value) })
        }
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: key(scope))
    }
    static func clear(scope: String) {
        generations[scope, default: 0] += 1
        UserDefaults.standard.removeObject(forKey: key(scope))
    }
    static func acceptsResult(scope: String, generation: Int) -> Bool {
        DataOwnership.activeScope == scope && generations[scope, default: 0] == generation
    }
    static func rememberSelection(_ completion: MKLocalSearchCompletion, address: String) {
        select(address: address) {
            let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
            return response.mapItems.map { item in
                let coordinate = item.location.coordinate
                return NavigationPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        }
    }
    @discardableResult static func select(address: String, resolve: @escaping @MainActor () async throws -> [NavigationPoint]) -> Task<Void, Never> {
        let scope = DataOwnership.activeScope
        let generation = generations[scope, default: 0]
        let selectionKey = scope + "|" + addressKey(address)
        let requestID = UUID()
        pendingSelections[selectionKey] = requestID
        // A fresh choice supersedes even an older cached choice with identical display text.
        var values = entries(scope)
        values.removeValue(forKey: addressKey(address))
        if let data = try? JSONEncoder().encode(values) { UserDefaults.standard.set(data, forKey: key(scope)) }
        return Task {
            defer { if pendingSelections[selectionKey] == requestID { pendingSelections.removeValue(forKey: selectionKey) } }
            do {
                // Resolve the selected completion itself, never re-search its display text.
                let points = try await resolve()
                guard !Task.isCancelled, points.count == 1, pendingSelections[selectionKey] == requestID,
                      acceptsResult(scope: scope, generation: generation) else { return }
                remember(points[0], for: address, scope: scope)
            } catch {
                // No coordinate is stored on failure; navigation must use the safe search fallback.
            }
        }
    }
}
