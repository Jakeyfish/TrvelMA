/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The top-level tab navigation for the app.
*/

import SwiftUI

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
    @Previewable @State var dataSource = DataSource()

    ContentView()
        .environment(dataSource)
}
