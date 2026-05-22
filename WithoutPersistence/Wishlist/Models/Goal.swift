/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
An aspirational challenge that tracks progress toward a target.
*/

import Foundation

/// An aspirational challenge that tracks progress toward a target.
enum Goal: CaseIterable {
    
    /// Complete 1 activity.
    case complete1Activity
    
    /// Complete 5 activities.
    case complete5Activities
    
    /// Complete 10 activities.
    case complete10Activities
    
    /// Complete 1 trip.
    case complete1Trip
    
    /// Complete 3 trips.
    case complete3Trips
    
    /// Complete 5 trips.
    case complete5Trips
    
    /// Complete 1 spring trip.
    case complete1SpringTrip
    
    /// Complete 3 spring trips.
    case complete3SpringTrips
    
    /// Complete 5 spring trips.
    case complete5SpringTrips
    
    /// Complete 1 summer trip.
    case complete1SummerTrip
    
    /// Complete 3 summer trips.
    case complete3SummerTrips
    
    /// Complete 5 summer trips.
    case complete5SummerTrips
    
    /// Complete 1 fall trip.
    case complete1FallTrip
    
    /// Complete 3 fall trips.
    case complete3FallTrips
    
    /// Complete 5 fall trips.
    case complete5FallTrips
    
    /// Complete 1 winter trip.
    case complete1WinterTrip
    
    /// Complete 3 winter trips.
    case complete3WinterTrips
    
    /// Complete 5 winter trips.
    case complete5WinterTrips
}

extension Goal: Identifiable {
    
    /// The unique identifier for the goal.
    var id: Self { self }
}

extension Goal {

    /// The display name of the goal.
    var name: String {
        switch self {
        case .complete1Activity: "First Activity"
        case .complete5Activities: "5 Activities"
        case .complete10Activities: "10 Activities"
        case .complete1Trip: "First Trip"
        case .complete3Trips: "3 Trips"
        case .complete5Trips: "5 Trips"
        case .complete1SpringTrip: "Spring Explorer"
        case .complete3SpringTrips: "3 Spring Trips"
        case .complete5SpringTrips: "5 Spring Trips"
        case .complete1SummerTrip: "Summer Explorer"
        case .complete3SummerTrips: "3 Summer Trips"
        case .complete5SummerTrips: "5 Summer Trips"
        case .complete1FallTrip: "Fall Explorer"
        case .complete3FallTrips: "3 Fall Trips"
        case .complete5FallTrips: "5 Fall Trips"
        case .complete1WinterTrip: "Winter Explorer"
        case .complete3WinterTrips: "3 Winter Trips"
        case .complete5WinterTrips: "5 Winter Trips"
        }
    }

    /// The name of the badge image awarded when the goal is completed.
    ///
    /// This corresponds to the name of the image in the asset catalog.
    var badgeName: String {
        switch kind {
        case .activitiesCompleted: "activities\(target)"
        case .tripsCompleted: "trips\(target)"
        case .collectionTripsCompleted(let collection): "\(collection.season)\(target)"
        }
    }

    /// The type of goal being tracked.
    var kind: Kind {
        switch self {
        case .complete1Activity, .complete5Activities, .complete10Activities:
            .activitiesCompleted
        case .complete1Trip, .complete3Trips, .complete5Trips:
            .tripsCompleted
        case .complete1SpringTrip, .complete3SpringTrips, .complete5SpringTrips:
            .collectionTripsCompleted(.springEscapes)
        case .complete1SummerTrip, .complete3SummerTrips, .complete5SummerTrips:
            .collectionTripsCompleted(.summerVibes)
        case .complete1FallTrip, .complete3FallTrips, .complete5FallTrips:
            .collectionTripsCompleted(.fallGetaways)
        case .complete1WinterTrip, .complete3WinterTrips, .complete5WinterTrips:
            .collectionTripsCompleted(.winterRetreats)
        }
    }

    /// The number required to complete the goal.
    var target: Int {
        switch self {
        case .complete1Activity, .complete1Trip, .complete1SpringTrip, .complete1SummerTrip, .complete1FallTrip, .complete1WinterTrip:
            1
        case .complete3Trips, .complete3SpringTrips, .complete3SummerTrips, .complete3FallTrips, .complete3WinterTrips:
            3
        case .complete5Activities, .complete5Trips, .complete5SpringTrips, .complete5SummerTrips, .complete5FallTrips, .complete5WinterTrips:
            5
        case .complete10Activities:
            10
        }
    }

    /// Returns the progress toward the goal as a value between 0 and 1.
    ///
    /// - Parameter currentCount: The current count toward the goal.
    /// - Returns: A value from 0 (no progress) to 1 (complete).
    func progress(for currentCount: Int) -> Double {
        min(Double(currentCount) / Double(target), 1.0)
    }

    /// Returns whether the goal has been achieved based on the given count.
    ///
    /// - Parameter currentCount: The current count toward the goal.
    /// - Returns: `true` if the goal has been achieved, `false` otherwise.
    func isAchieved(for currentCount: Int) -> Bool {
        currentCount >= target
    }
}

extension Goal {
    /// The types of goals that can be tracked.
    enum Kind: Hashable {

        /// The number of trips completed.
        case tripsCompleted

        /// The number of activities completed.
        case activitiesCompleted

        /// The number of trips completed in a specific collection.
        case collectionTripsCompleted(TripCollection)
    }
}
