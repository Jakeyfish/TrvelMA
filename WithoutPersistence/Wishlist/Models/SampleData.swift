/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The app's sample data.
*/

import Foundation

/// The app's sample data.
struct SampleData {

    /// All sample trips with their associated collections.
    static let allTrips: [Trip] = [
        Trip(
            name: "Cali Coastal Trails",
            collection: .springEscapes,
            photoURL: bundleURL(for: "CoastalTrail", withExtension: "jpeg"),
            activities: [
                Activity(name: "Hike Swallow's Point Trail"),
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
            photoURL: bundleURL(for: "Shore", withExtension: "jpeg"),
            activities: [
                Activity(name: "Surf at Pleasure Point"),
                Activity(name: "Watch the pros at Steamer Lane"),
                Activity(name: "Practice for Steamer Lane")
            ]
        ),
        Trip(
            name: "Japan Mystique",
            collection: .springEscapes,
            photoURL: bundleURL(for: "Japan", withExtension: "jpeg"),
            activities: [
                Activity(name: "Walk the canal paths at sunrise"),
                Activity(name: "Visit the hillside wooden temples"),
                Activity(name: "Get Matcha soft serve in Gion")
            ]
        ),
        Trip(
            name: "Mont Blanc Powder",
            collection: .springEscapes,
            photoURL: bundleURL(for: "MontBlanc", withExtension: "jpeg"),
            activities: [
                Activity(name: "Snowboarding in a t-shirt"),
                Activity(name: "Snowshoe hike")
            ]
        ),
        Trip(
            name: "Braving the Narrows",
            collection: .fallGetaways,
            photoURL: bundleURL(for: "Zion", withExtension: "jpeg"),
            activities: [
                Activity(name: "Hike the river canyon from the bottom up", isComplete: true),
                Activity(name: "Stargazing near the canyon campgrounds", isComplete: true)
            ]
        ),
        Trip(
            name: "Into the Green",
            collection: .fallGetaways,
            photoURL: bundleURL(for: "Waterfall", withExtension: "jpeg"),
            activities: [
                Activity(name: "Cliff jump!"),
                Activity(name: "Snorkel through caves with stalactites"),
                Activity(name: "Hop on a bike and explore the jungle")
            ]
        ),
        Trip(
            name: "Angkor Temple Run",
            collection: .winterRetreats,
            photoURL: bundleURL(for: "Bridge", withExtension: "jpeg"),
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
            photoURL: bundleURL(for: "JoshuaTree", withExtension: "jpeg"),
            activities: [
                Activity(name: "Hike Warren Peak"),
                Activity(name: "Climb those huge boulder formations!"),
                Activity(name: "Sound bath meditation in the desert")
            ]
        ),
        Trip(
            name: "Hunting Auroras",
            collection: .winterRetreats,
            photoURL: bundleURL(for: "Aurora", withExtension: "jpeg"),
            activities: [
                Activity(name: "Relax in a lagoon in the snowy lava fields"),
                Activity(name: "Take a tour to hunt the lights!"),
                Activity(name: "Walk behind the Seljalandsfoss waterfall")
            ]
        ),
        Trip(
            name: "Kona Deep Dive",
            collection: .summerVibes,
            photoURL: bundleURL(for: "HawaiiCoast", withExtension: "jpeg"),
            activities: [
                Activity(name: "Snorkel through the lava tubes"),
                Activity(name: "Spot migrating humpback whales"),
                Activity(name: "Night snorkel with manta rays")
            ]
        ),
        Trip(
            name: "Desert Off-Road",
            collection: .fallGetaways,
            photoURL: bundleURL(for: "SandDune", withExtension: "jpeg"),
            activities: [
                Activity(name: "Buggy ride across the ridges", isComplete: true),
                Activity(name: "Sandboard", isComplete: true)
            ]
        ),
        Trip(
            name: "Maui Rainforest",
            collection: .summerVibes,
            photoURL: bundleURL(for: "Lizard", withExtension: "jpeg"),
            activities: [
                Activity(name: "Descend a waterfall"),
                Activity(name: "Relax in the volcanic hot springs")
            ]
        )
    ]
}

private extension SampleData {
    
    /// Returns the file URL from the bundle for the file identified by
    /// the specified name and file extension.
    ///
    /// - Parameters:
    ///   - name: The name of the file.
    ///   - fileExtension: The extension of the file.
    /// - Returns: The URL for the file.
   static func bundleURL(for name: String, withExtension fileExtension: String) -> URL {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            fatalError("Could not find resource '\(name).\(fileExtension)' in main bundle")
        }
        return url
    }
}
