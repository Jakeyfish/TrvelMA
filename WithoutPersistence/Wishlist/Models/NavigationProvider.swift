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
        let point = NavigationPoint.parse(destination) ?? NavigationDestinationStore.point(for: destination)

        var components: URLComponents?
        switch self {
        case .appleMaps:
            components = URLComponents(string: "https://maps.apple.com/")
            components?.queryItems = [
                URLQueryItem(name: point == nil ? "q" : "daddr", value: point?.queryValue ?? destination)
            ]
            if point != nil { components?.queryItems?.append(URLQueryItem(name: "dirflg", value: "d")) }
        case .googleMaps:
            components = URLComponents(string: point == nil ? "https://www.google.com/maps/search/" : "https://www.google.com/maps/dir/")
            components?.queryItems = [
                URLQueryItem(name: "api", value: "1"),
                URLQueryItem(name: point == nil ? "query" : "destination", value: point?.queryValue ?? destination)
            ]
            if point != nil { components?.queryItems?.append(URLQueryItem(name: "travelmode", value: "driving")) }
        }
        return components?.url
    }
}
