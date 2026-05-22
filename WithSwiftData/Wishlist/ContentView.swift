/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The top-level tab navigation for the app.
*/

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Wishlist", systemImage: "rainbow") {
                WishlistView()
            }

            Tab("Goals", systemImage: "star.hexagon") {
                GoalsView()
            }
            
            Tab(role: .search) {
                SearchView()
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(SampleData.previewContainer)
}
