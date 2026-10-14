/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A named collection of related trips.
*/

import Foundation

/// A named collection of related trips.
enum TripCollection: String, CaseIterable {

    /// A collection of trips planned for the spring.
    case springEscapes

    /// A collection of trips planned for the summer.
    case summerVibes

    /// A collection of trips planned for the fall.
    case fallGetaways

    /// A collection of trips planned for the winter.
    case winterRetreats
}

extension TripCollection: Identifiable {
    var id: Self { self }
}

extension TripCollection {

    /// The display name of the collection.
    var name: String {
        switch self {
        case .springEscapes: "春日出游"
        case .summerVibes: "夏日畅游"
        case .fallGetaways: "秋日旅行"
        case .winterRetreats: "冬日静居"
        }
    }
    
    /// A brief description summarizing the collection.
    var summary: String? {
        switch self {
        case .summerVibes: "尽情享受公路、海浪与漫长日光"
        default: nil
        }
    }

    /// The name of the season corresponding to the trip collection.
    var season: String {
        switch self {
        case .springEscapes: "spring"
        case .summerVibes: "summer"
        case .fallGetaways: "fall"
        case .winterRetreats: "winter"
        }
    }
}
