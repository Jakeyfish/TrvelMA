/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The available sorting options for activities.
*/

import Foundation
import SwiftData

/// The available sorting options for activities.
enum SortOption: String, CaseIterable, Identifiable {

    var id: String { title }

    /// Sort by title, ascending.
    case title

    /// Sort by date created, ascending.
    case dateCreated

    /// Sort by date edited, ascending.
    case dateEdited

    /// Sort by completed status, with completed items last.
    case completed

    var title: String {
        switch self {
        case .title: "Title"
        case .dateCreated: "Date Created"
        case .dateEdited: "Date Edited"
        case .completed: "Completed"
        }
    }

    var sortDescriptors: [SortDescriptor<Activity>] {
        switch self {
        case .title:
            [SortDescriptor(\Activity.name)]
        case .dateCreated:
            [SortDescriptor(\Activity.dateCreated, order: .reverse),
             SortDescriptor(\Activity.name)]
        case .dateEdited:
            [SortDescriptor(\Activity.dateEdited, order: .reverse),
             SortDescriptor(\Activity.name)]
        case .completed:
            [SortDescriptor(\Activity.isComplete, order: .forward),
             SortDescriptor(\Activity.name)]
        }
    }
}
