/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The available sorting options for activities.
*/

import Foundation

/// The available sorting options for activities.
enum SortOption: String, CaseIterable, Identifiable {

    var id: String { title }

    /// Sort by title, ascending.
    case title

    /// Sort by date created, ascending.
    case dateCreated

    /// Sort by date edited, ascending.
    case dateEdited

    /// Sort by completed status, with completed items first.
    case completed

    var title: String {
        switch self {
        case .title: "标题"
        case .dateCreated: "建立日期"
        case .dateEdited: "修改日期"
        case .completed: "已完成"
        }
    }
}

/// Extension for sorting arrays of activities.
extension Array where Element == Activity {

    /// Sorts the activities array in place based on the specified sort option.
    /// - Parameter sortOption: The sorting criteria to apply
    mutating func sort(by sortOption: SortOption) {
        switch sortOption {
        case .title:
            sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .dateCreated:
            sort {
                if $0.dateCreated != $1.dateCreated {
                    return $0.dateCreated > $1.dateCreated
                } else {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
        case .dateEdited:
            sort {
                if $0.dateEdited != $1.dateEdited {
                    return $0.dateEdited > $1.dateEdited
                } else {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
        case .completed:
            sort {
                if $0.isComplete != $1.isComplete {
                    return $0.isComplete && !$1.isComplete
                } else {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
        }
    }
}
