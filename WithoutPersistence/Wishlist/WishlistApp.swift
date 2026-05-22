/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The main app structure.
*/

import SwiftUI

@main
struct WishlistApp: App {

    /// The data source provides trip data to this view and its descendants.
    @State private var dataSource = DataSource()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(dataSource)
                .preferredColorScheme(.dark)
        }
    }
}
