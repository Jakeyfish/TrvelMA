/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Displays recent trips, explorer goals, and trip collections.
*/

import SwiftUI
import SwiftData

/// The main wishlist view displaying trip-related content.
///
/// This view serves as the primary interface for browsing trips in
/// a vertically scrolling layout.
struct WishlistView: View {

    /// Indicates whether the sheet to add a trip is being presented.
    @State private var isPresentingAddTrip = false

    /// The namespace used for coordinating a navigation transition.
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    // Paged tab showing recent trips.
                    RecentTripsPageView()
                        .padding(.bottom, 20)

                    // All trip collections.
                    ForEach(TripCollection.allCases) { tripCollection in
                        TripCollectionView(
                            tripCollection: tripCollection,
                            cardSize: tripCollection.cardSize,
                            namespace: namespace
                        )
                    }
                }
            }
            .contentMargins(.bottom, 30, for: .scrollContent)
            .ignoresSafeArea(edges: .top)
            .toolbar {
                // To customize the font of the navigation title, or add
                // other custom views, use a toolbar item with the title
                // placement.
                ToolbarItem(placement: .title) {
                    ExpandedNavigationTitle(title: "Wishlist")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingAddTrip = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .matchedTransitionSource(id: "addTrip", in: namespace)
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
                }
            }
            .sheet(isPresented: $isPresentingAddTrip) {
                AddTripView(isPresented: $isPresentingAddTrip)
                    .navigationTransition(
                        .zoom(sourceID: "addTrip", in: namespace))
            }
            // Always add a navigation title. It's used for the
            // accessibility label when navigating back from a detail view.
            .navigationTitle("Wishlist")
            .toolbarTitleDisplayMode(.inline)
            // Leading-align the custom title.
            .toolbarRole(.editor)
        }
    }
}

private extension TripCollection {

    /// Returns the appropriate card size for a trip collection.
    ///
    /// Determines the card size based on whether the collection has a summary:
    /// - `.expanded` for collections that have a summary.
    /// - `.compact` for collections without a summary.
    var cardSize: TripCard.Size {
        (summary?.isEmpty == false) ? .expanded : .compact
    }
}

#Preview {
    WishlistView()
        .modelContainer(SampleData.previewContainer)
}
