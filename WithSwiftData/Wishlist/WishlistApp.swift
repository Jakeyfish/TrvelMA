/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The main app structure.
*/

import SwiftUI
import SwiftData

@main
struct WishlistApp: App {

    let container: ModelContainer = {
        do {
            let modelContainer = try ModelContainer(for: Trip.self, Activity.self, TripImage.self, Goal.self, TripGoal.self, ActivityGoal.self)
            try SampleData.seedIfNeeded(in: modelContainer.mainContext)
            return modelContainer
        } catch {
            fatalError("Could not create model container: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
