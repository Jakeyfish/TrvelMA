/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The app's sample data.
*/

import Foundation
import SwiftData

/// The app's sample data.
struct SampleData {

    static func seedIfNeeded(in context: ModelContext) throws {
        let activityGoalFetchDescriptor = FetchDescriptor<ActivityGoal>(fetchLimit: 1)

        if try context.fetchCount(activityGoalFetchDescriptor) == 0 {
            let completedActivitiesCount = Self.allTrips.reduce(0) { partialResult, trip in
                partialResult + trip.activities.count { $0.isComplete }
            }

            for goal in Self.allActivityGoals {
                goal.completedCount = completedActivitiesCount
                if !goal.isAchieved && goal.completedCount >= goal.target {
                    goal.isAchieved = true
                    goal.dateAchieved = .now
                }
                context.insert(goal)
            }
        }

        let tripGoalFetchDescriptor = FetchDescriptor<TripGoal>(fetchLimit: 1)

        if try context.fetchCount(tripGoalFetchDescriptor) == 0 {
            for goal in Self.allTripGoals {
                let completedTripsCount = Self.allTrips.count { $0.isComplete && (goal.collection == nil || $0.collection == goal.collection) }
                goal.completedCount = completedTripsCount
                if !goal.isAchieved && goal.completedCount >= goal.target {
                    goal.isAchieved = true
                    goal.dateAchieved = .now
                }
                context.insert(goal)
            }
        }

        let tripFetchDescriptor = FetchDescriptor<Trip>(fetchLimit: 1)

        if try context.fetchCount(tripFetchDescriptor) == 0 {
            for trip in Self.allTrips {
                context.insert(trip)
            }
        }

        try context.save()
    }

    /// All sample trips with their associated collections.
    private static let allTrips: [Trip] = [
        Trip(
            name: "Cali Coastal Trails",
            collection: .springEscapes,
            photo: TripImage(name: "CoastalTrail"),
            activities: [
                Activity(name: "Hike Swallow’s Point Trail"),
                Activity(name: "Photograph the cypress tree tunnel"),
                Activity(name: "Hike the cliffs of Big Sur", isComplete: true),
                Activity(name: "Explore Laguna Beach tide pools"),
                Activity(name: "Bike the Monterey Bay Trail"),
                Activity(name: "See the elk herd at Point Reyes", isComplete: true)
            ]
        ),
        Trip(
            name: "Surf Steamer Lane",
            collection: .summerVibes,
            photo: TripImage(name: "Shore"),
            activities: [
                Activity(name: "Surf at Pleasure Point"),
                Activity(name: "Watch the pros at Steamer Lane"),
                Activity(name: "Practice for Steamer Lane")
            ]
        ),
        Trip(
            name: "Japan Mystique",
            collection: .springEscapes,
            photo: TripImage(name: "Japan"),
            activities: [
                Activity(name: "Walk the canal paths at sunrise"),
                Activity(name: "Visit the hillside wooden temples"),
                Activity(name: "Get Matcha soft serve in Gion")
            ]
        ),
        Trip(
            name: "Mont Blanc Powder",
            collection: .springEscapes,
            photo: TripImage(name: "MontBlanc"),
            activities: [
                Activity(name: "Snowboarding in a t-shirt"),
                Activity(name: "Snowshoe hike")
            ]
        ),
        Trip(
            name: "Braving the Narrows",
            collection: .fallGetaways,
            photo: TripImage(name: "Zion"),
            activities: [
                Activity(name: "Hike the river canyon from the bottom up", isComplete: true),
                Activity(name: "Stargazing near the canyon campgrounds", isComplete: true)
            ]
        ),
        Trip(
            name: "Into the Green",
            collection: .fallGetaways,
            photo: TripImage(name: "Waterfall"),
            activities: [
                Activity(name: "Cliff jump!"),
                Activity(name: "Snorkel through caves with stalactites"),
                Activity(name: "Hop on a bike and explore the jungle")
            ]
        ),
        Trip(
            name: "Angkor Temple Run",
            collection: .winterRetreats,
            photo: TripImage(name: "Bridge"),
            activities: [
                Activity(name: "Watch the sunrise over the temple lotus ponds", isComplete: true),
                Activity(name: "Hike through the jungle temples", isComplete: true),
                Activity(name: "Browse the night markets", isComplete: true),
                Activity(name: "Hop on a tuk-tuk tour"),
                Activity(name: "Take a scenic balloon ride")
            ]
        ),
        Trip(
            name: "Hike Joshua Tree",
            collection: .winterRetreats,
            photo: TripImage(name: "JoshuaTree"),
            activities: [
                Activity(name: "Hike Warren Peak"),
                Activity(name: "Climb those huge boulder formations!"),
                Activity(name: "Sound bath meditation in the desert")
            ]
        ),
        Trip(
            name: "Hunting Auroras",
            collection: .winterRetreats,
            photo: TripImage(name: "Aurora"),
            activities: [
                Activity(name: "Relax in a lagoon in the snowy lava fields"),
                Activity(name: "Take a tour to hunt the lights!"),
                Activity(name: "Walk behind the Seljalandsfoss waterfall")
            ]
        ),
        Trip(
            name: "Kona Deep Dive",
            collection: .summerVibes,
            photo: TripImage(name: "HawaiiCoast"),
            activities: [
                Activity(name: "Snorkel through the lava tubes"),
                Activity(name: "Spot migrating humpback whales"),
                Activity(name: "Night snorkel with manta rays")
            ]
        ),
        Trip(
            name: "Desert Off-Road",
            collection: .fallGetaways,
            photo: TripImage(name: "SandDune"),
            activities: [
                Activity(name: "Buggy ride across the ridges", isComplete: true),
                Activity(name: "Sandboard", isComplete: true)
            ]
        ),
        Trip(
            name: "Maui Rainforest",
            collection: .summerVibes,
            photo: TripImage(name: "Lizard"),
            activities: [
                Activity(name: "Descend a waterfall"),
                Activity(name: "Relax in the volcanic hot springs")
            ]
        )
    ]

    private static let allTripGoals: [TripGoal] = [
        TripGoal(name: "First Trip", target: 1, sortOrder: 0),
        TripGoal(name: "3 Trips", target: 3, sortOrder: 1),
        TripGoal(name: "5 Trips", target: 5, sortOrder: 2),
        TripGoal(name: "Spring Explorer", target: 1, sortOrder: 3, collection: .springEscapes),
        TripGoal(name: "3 Spring Trips", target: 3, sortOrder: 4, collection: .springEscapes),
        TripGoal(name: "5 Spring Trips", target: 5, sortOrder: 5, collection: .springEscapes),
        TripGoal(name: "Summer Explorer", target: 1, sortOrder: 6, collection: .summerVibes),
        TripGoal(name: "3 Summer Trips", target: 3, sortOrder: 7, collection: .summerVibes),
        TripGoal(name: "5 Summer Trips", target: 5, sortOrder: 8, collection: .summerVibes),
        TripGoal(name: "Fall Explorer", target: 1, sortOrder: 9, collection: .fallGetaways),
        TripGoal(name: "3 Fall Trips", target: 3, sortOrder: 10, collection: .fallGetaways),
        TripGoal(name: "5 Fall Trips", target: 5, sortOrder: 11, collection: .fallGetaways),
        TripGoal(name: "Winter Explorer", target: 1, sortOrder: 12, collection: .winterRetreats),
        TripGoal(name: "3 Winter Trips", target: 3, sortOrder: 13, collection: .winterRetreats),
        TripGoal(name: "5 Winter Trips", target: 5, sortOrder: 14, collection: .winterRetreats)
    ]

    private static let allActivityGoals: [ActivityGoal] = [
        ActivityGoal(name: "First Activity", target: 1, sortOrder: 0),
        ActivityGoal(name: "5 Activities", target: 5, sortOrder: 1),
        ActivityGoal(name: "10 Activities", target: 10, sortOrder: 2)
    ]

    /// A shared container for SwiftData previews.
    static let previewContainer: ModelContainer = {
        do {
            let container = try ModelContainer(
                for: Trip.self, Activity.self, TripImage.self, Goal.self, TripGoal.self, ActivityGoal.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            try SampleData.seedIfNeeded(in: container.mainContext)
            return container
        } catch {
            fatalError("Could not create model container for preview: \(error)")
        }
    }()
}

extension FetchDescriptor {
    init(predicate: Predicate<T>? = nil, sortBy: [SortDescriptor<T>] = [], fetchLimit: Int) {
        self.init(predicate: predicate, sortBy: sortBy)
        self.fetchLimit = fetchLimit
    }
}
