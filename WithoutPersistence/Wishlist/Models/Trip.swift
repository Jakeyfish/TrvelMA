/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A travel trip with a name, activities, and associated photo.
*/

import Foundation

/// A travel trip with a name, activities, and associated photo.
@Observable
class Trip: Identifiable {

    /// The name of the trip.
    var name: String
    
    /// The collection this trip belongs to.
    var collection: TripCollection
    
    /// The URL of the photo associated with the trip.
    var photoURL: URL

    /// The activities associated with the trip.
    ///
    /// The dictionary allows for efficient lookup of activities by their IDs,
    /// without iterating through the collection.
    var activities: [Activity.ID: Activity]

    /// The date and time when the trip was created.
    let creationDate = Date.now

    /// The subtitle for the trip that provides additional descriptive text.
    var subtitle: String?

    /// Creates a new trip with the specified details.
    ///
    /// - Parameters:
    ///   - name: The name of the trip.
    ///   - collection: The collection this trip belongs to.
    ///   - photoURL: The URL of the photo associated with the trip.
    ///   - activities: Optional; The activities associated with this trip.
    ///     Defaults to an empty collection.
    ///   - subtitle: Optional; The subtitle for the trip that provides additional descriptive text.
    init(
        name: String,
        collection: TripCollection,
        photoURL: URL,
        activities: [Activity] = [],
        subtitle: String? = nil
    ) {
        self.name = name
        self.collection = collection
        self.photoURL = photoURL
        self.activities = Dictionary(uniqueKeysWithValues: activities.map { ($0.id, $0) })
        self.subtitle = subtitle
    }
}
