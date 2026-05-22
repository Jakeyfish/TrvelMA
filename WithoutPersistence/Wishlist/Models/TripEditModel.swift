/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The model that manages the editing state for a trip.
*/

import SwiftUI

/// The model that manages the editing state for a trip.
@Observable
class TripEditModel {

    /// The trip being edited.
    var trip: Trip

    /// The URL of the trip's photo.
    var photoURL: URL { trip.photoURL }

    /// The name of the trip.
    var name: String { trip.name }

    /// The list of activities being edited.
    var activities: [Activity]

    /// Indicates whether the trip is currently in editing mode.
    ///
    /// When set to `true`, the model loads the trip's current data for editing.
    /// When set to `false`, any changes are committed back to the trip object.
    var isEditing = false

    /// Creates a new edit model for the specified trip.
    ///
    /// - Parameter trip: The trip to create an edit model for.
    init(trip: Trip) {
        self.trip = trip
        self.activities = Array(trip.activities.values)
    }
}

extension TripEditModel {

    /// The progress value as a fraction between 0.0 and 1.0.
    var progressValue: Double {
        guard !activities.isEmpty else { return 0.0 }
        let completedCount = activities.filter { $0.isComplete }.count
        return Double(completedCount) / Double(activities.count)
    }

    /// Saves the current activities back to the trip.
    func saveActivities(dataSource: DataSource) {
        let validActivities = activities.filter { !$0.name.isEmpty }
        let activityPairs = validActivities.map { ($0.id, $0) }
        trip.activities = Dictionary(uniqueKeysWithValues: activityPairs)
        dataSource.trips[trip.id] = trip
    }

    /// Adds a new empty activity to the activities list and enters editing mode.
    func addNewActivity() {
        activities.append(Activity(name: ""))
        isEditing = true
    }

    /// Removes the specified activity from the activities list.
    ///
    /// - Parameter activity: The activity to remove from the trip.
    func removeActivity(_ activity: Activity) {
        activities.removeAll(where: { $0.id == activity.id })
    }
}
