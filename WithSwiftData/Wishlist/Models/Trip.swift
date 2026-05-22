/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A travel trip with a name, activities, and associated photo.
*/

import Foundation
import SwiftData

/// A travel trip with a name, activities, and associated photo.
@Model
class Trip {

    /// The name of the trip.
    var name: String

    /// The collection this trip belongs to.
    var collection: TripCollection

    /// The full-size photo associated with the trip.
    var photo: TripImage

    var thumbnailData: Data?

    /// The activities associated with the trip.
    @Relationship(deleteRule: .cascade, inverse: \Activity.trip)
    var activities: [Activity] = []

    /// The date and time when the person created the trip.
    private(set) var creationDate = Date.now

    /// The subtitle for the trip that provides additional descriptive text.
    var subtitle: String?

    /// Indicates whether the person completed all the activities in the trip.
    var isComplete: Bool = false

    /// The progress value as a fraction between 0.0 and 1.0.
    var progressValue: Double {
        guard !activities.isEmpty else { return 0.0 }
        let completedCount = activities.filter { $0.isComplete }.count
        return Double(completedCount) / Double(activities.count)
    }

    /// Creates a new trip with the specified details.
    ///
    /// - Parameters:
    ///   - name: The name of the trip.
    ///   - collection: The collection this trip belongs to.
    ///   - photo: The photo associated with the trip.
    ///   - activities: Optional; The activities associated with this trip.
    ///     Defaults to an empty collection.
    ///   - subtitle: Optional; The subtitle for the trip that provides additional descriptive text.
    init(
        name: String,
        collection: TripCollection,
        photo: TripImage,
        activities: [Activity] = [],
        subtitle: String? = nil
    ) {
        self.name = name
        self.collection = collection
        self.photo = photo
        self.activities = activities
        self.subtitle = subtitle
        self.isComplete = !activities.isEmpty && activities.allSatisfy { $0.isComplete }
        self.thumbnailData = TripImage.thumbnailData(from: photo.data)
    }
}
