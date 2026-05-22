/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
An activity within a trip, with a name and completion status.
*/

import Foundation
import SwiftData

/// An activity within a trip, with a name and completion status.
@Model
class Activity {

    /// The name of the activity.
    var name: String

    /// Indicates whether the activity has been completed.
    var isComplete: Bool

    /// The date when the activity was created.
    var dateCreated = Date.now

    /// The date when the activity was last edited.
    var dateEdited = Date.now

    var trip: Trip?

    @Transient var token: ObservationTracking.Token?

    /// Creates a new activity with the specified details.
    ///
    /// - Parameters:
    ///   - name: The display name of the activity.
    ///   - isComplete: Optional; Indicates whether the activity has been
    ///     completed. Defaults to false.
    init(name: String, isComplete: Bool = false) {
        self.name = name
        self.isComplete = isComplete
    }
}
