/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
An aspirational challenge that tracks progress toward a target.
*/

import Foundation
import SwiftData

/// An aspirational challenge that tracks progress toward a target.
@Model
class Goal {

    var name: String

    var target: Int

    /// The name of the image in the asset catalog.
    var badgeName: String

    /// Controls display ordering in the Goals tab.
    var sortOrder: Int

    /// The number of completed items counting toward this goal.
    var completedCount: Int

    var dateAchieved: Date?

    /// Whether the person has achieved the goal based on progress made toward the target count.
    var isAchieved: Bool

    /// Returns the progress toward the goal as a value between 0 and 1.
    var progressValue: Double {
        min(Double(completedCount) / Double(target), 1.0)
    }

    init(name: String, target: Int, badgeName: String, sortOrder: Int, completedCount: Int = 0) {
        self.name = name
        self.target = target
        self.badgeName = badgeName
        self.sortOrder = sortOrder
        self.completedCount = completedCount
        self.isAchieved = completedCount >= target
    }

    /// A subtitle describing how the person earned this award.
    var subtitle: String {
        if let dateAchieved {
            "You earned this award on \(dateAchieved)."
        } else {
            "You have not yet earned this award."
        }
    }

    fileprivate var ordinalModifier: String {
        target == 1 ? "first" : "\(target.ordinal)"
    }
}

@Model
@available(iOS 26, *)
class TripGoal: Goal {

    var collection: TripCollection?

    init(name: String, target: Int, sortOrder: Int, collection: TripCollection? = nil) {
        self.collection = collection
        super.init(name: name, target: target, badgeName: "trips\(target)", sortOrder: sortOrder)
    }

    override var ordinalModifier: String {
        if let collection {
            return "\(super.ordinalModifier) \(collection.season)"
        } else {
            return super.ordinalModifier
        }
    }

    override var subtitle: String {
        "You earned this award for completing your \(self.ordinalModifier) trip in your Wishlist."
    }
}

@Model
@available(iOS 26, *)
class ActivityGoal: Goal {

    /// The trip on which the person achieved this goal.
    var tripAchieved: Trip?

    init(name: String, target: Int, sortOrder: Int, tripAchieved: Trip? = nil) {
        self.tripAchieved = tripAchieved
        super.init(name: name, target: target, badgeName: "activities\(target)", sortOrder: sortOrder)
    }

    override var subtitle: String {
        "You earned this award for completing your \(self.ordinalModifier) trip activity."
    }
}

// MARK: - Ordinal formatting

private extension Int {

    /// Returns the ordinal string representation of this integer (e.g., "1st", "2nd", "3rd", "5th").
    nonisolated var ordinal: String {
        Self.ordinalFormatter.string(from: self as NSNumber) ?? "\(self)"
    }

    /// A formatter for converting integers to ordinal strings.
    nonisolated private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()
}
