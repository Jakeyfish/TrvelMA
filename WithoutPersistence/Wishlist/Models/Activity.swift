/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
An activity within a trip, with a name and completion status.
*/

import SwiftUI

/// An activity within a trip, with a name and completion status.
@Observable
class Activity: Identifiable {
    /// A unique identifier for the activity.
    let id = UUID()

    /// The name of the activity.
    var name: String {
        didSet {
            // Update edit timestamp when name changes.
            dateEdited = .now
        }
    }

    /// Indicates whether the activity has been completed.
    var isComplete = false {
        didSet {
            // Update edit timestamp when completion status changes.
            dateEdited = .now
        }
    }

    /// The date when the activity was created.
    var dateCreated = Date.now

    /// The date when the activity was last edited.
    var dateEdited = Date.now

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
