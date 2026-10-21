import Foundation

enum NavigationProvider: String, CaseIterable, Identifiable {
    case appleMaps
    case googleMaps

    static var defaultsKey: String { "defaultNavigationProvider.\(DataOwnership.activeScope)" }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleMaps: "Apple 地图"
        case .googleMaps: "Google Maps"
        }
    }

    var symbol: String {
        switch self {
        case .appleMaps: "map.fill"
        case .googleMaps: "globe.americas.fill"
        }
    }

    static var selected: NavigationProvider {
        let rawValue = UserDefaults.standard.string(forKey: defaultsKey)
        return rawValue.flatMap(NavigationProvider.init(rawValue:)) ?? .appleMaps
    }

    func directionsURL(for address: String) -> URL? {
        let destination = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return nil }

        var components: URLComponents?
        switch self {
        case .appleMaps:
            components = URLComponents(string: "https://maps.apple.com/")
            components?.queryItems = [
                URLQueryItem(name: "daddr", value: destination),
                URLQueryItem(name: "dirflg", value: "d")
            ]
        case .googleMaps:
            components = URLComponents(string: "https://www.google.com/maps/dir/")
            components?.queryItems = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: "destination", value: destination),
                URLQueryItem(name: "travelmode", value: "driving")
            ]
        }
        return components?.url
    }
}
