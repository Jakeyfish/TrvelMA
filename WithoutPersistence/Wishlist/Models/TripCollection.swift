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
        case .springEscapes: "Spring Escapes"
        case .summerVibes: "Summer Vibes"
        case .fallGetaways: "Fall Getaways"
        case .winterRetreats: "Winter Retreats"
        }
    }
    
    /// A brief description summarizing the collection.
    var summary: String? {
        switch self {
        case .summerVibes: "Soak up open roads, salt water, and endless daylight"
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
