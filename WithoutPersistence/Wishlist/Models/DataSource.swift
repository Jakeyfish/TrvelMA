/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Manages trips, trip collections, and search input.
*/

import SwiftUI

/// Manages trips, trip collections, and search input for the app.
///
/// Use `DataSource` to access available trip collections,
/// and recently added trips. This class is observable,
/// so SwiftUI views will automatically update when its properties change.
@Observable
class DataSource {

    // MARK: - Initialization

    /// Creates a new data source, loading sample data and computing initial goal achievements.
    init() {
        self.trips = SampleData.allTrips.reduce(into: [:]) { result, trip in
            result[trip.id] = trip
        }
        updateGoalAchievements()
    }

    // MARK: - Search

    /// The current search query text.
    var searchText = ""

    // MARK: - Trips

    /// All trips, keyed by their ID.
    ///
    /// The dictionary allows for efficient lookup of trips by their IDs.
    var trips: [Trip.ID: Trip] {
        didSet {
            updateGoalAchievements()
        }
    }
    
    /// Returns the trips belonging to a specific collection.
    ///
    /// - Parameter collection: The collection to filter by.
    /// - Returns: An array of trips in the specified collection, sorted by name.
    func trips(in collection: TripCollection) -> [Trip] {
        trips.values
            .filter { $0.collection == collection }
            .sorted { $0.name < $1.name }
    }

    /// The five most recently created trips, sorted from newest to oldest.
    var recentlyAddedTrips: [Trip] {
        let allTrips = trips.values
        let sortedByNewest = allTrips.sorted { $0.creationDate > $1.creationDate }
        let topFive = sortedByNewest.prefix(5)
        return Array(topFive)
    }

    /// Finds and returns the trip that contains the specified activity.
    ///
    /// - Parameter activityId: The unique identifier of the activity to look for.
    /// - Returns: The trip containing the activity with the provided
    ///   identifier, or `nil` if no matching trip is found.
    func trip(containing activityId: Activity.ID) -> Trip? {
        trips.values.first { trip in
            trip.activities[activityId] != nil
        }
    }

    // MARK: - Goals

    /// All available goals.
    var goals: [Goal] = Goal.allCases

    /// The dates when goals were achieved, keyed by goal ID.
    private var achievementDates: [Goal.ID: Date] = [:]

    /// Returns the date a goal was achieved, or `nil` if not yet achieved.
    ///
    /// - Parameter goal: The goal to check.
    /// - Returns: The date the goal was achieved, or `nil` if not yet achieved.
    func dateAchieved(for goal: Goal) -> Date? {
        achievementDates[goal.id]
    }

    /// Returns the number of completed items for the given goal kind.
    ///
    /// - Parameter kind: The goal kind to count completions for.
    /// - Returns: The total number of completed trips or activities, depending on the goal kind.
    func completedCount(for kind: Goal.Kind) -> Int {
        switch kind {
        case .tripsCompleted:
            trips.values.filter { $0.isComplete }.count
        case .activitiesCompleted:
            trips.values.flatMap { $0.activities.values }.filter { $0.isComplete }.count
        case .collectionTripsCompleted(let collection):
            trips.values
                .filter { $0.collection == collection && $0.isComplete }
                .count
        }
    }

    /// Checks all goals and updates achievement dates based on current progress.
    ///
    /// Goals that are newly achieved will have their achievement date set to now.
    /// Goals that are no longer achieved (due to unchecked activities) will have
    /// their achievement date removed.
    ///
    /// Call this method whenever activities or trips are updated to ensure
    /// goal achievements are tracked correctly.
    func updateGoalAchievements() {
        // Compute counts once for each kind.
        let counts: [Goal.Kind: Int] = [
            .tripsCompleted: completedCount(for: .tripsCompleted),
            .activitiesCompleted: completedCount(for: .activitiesCompleted),
            .collectionTripsCompleted(.springEscapes): completedCount(for: .collectionTripsCompleted(.springEscapes)),
            .collectionTripsCompleted(.summerVibes): completedCount(for: .collectionTripsCompleted(.summerVibes)),
            .collectionTripsCompleted(.fallGetaways): completedCount(for: .collectionTripsCompleted(.fallGetaways)),
            .collectionTripsCompleted(.winterRetreats): completedCount(for: .collectionTripsCompleted(.winterRetreats))
        ]

        for goal in goals {
            let count = counts[goal.kind, default: 0]
            let wasAlreadyAchieved = achievementDates[goal.id] != nil
            let isNowAchieved = goal.isAchieved(for: count)

            if isNowAchieved && !wasAlreadyAchieved {
                // Goal newly achieved.
                achievementDates[goal.id] = .now
            } else if !isNowAchieved && wasAlreadyAchieved {
                // Goal no longer achieved.
                achievementDates[goal.id] = nil
            }
        }
    }

    /// Removes all user-created in-memory trip data and search state.
    func clearAllUserData() {
        searchText = ""
        trips = [:]
        achievementDates = [:]
    }
}

// MARK: - Trip Extension

private extension Trip {
    
    /// Indicates whether all the activities in the trip have been completed.
    ///
    /// A trip is only considered complete if it has at least one activity
    /// and all activities are marked as complete.
    var isComplete: Bool {
        !activities.isEmpty && activities.values.allSatisfy { $0.isComplete }
    }
}
