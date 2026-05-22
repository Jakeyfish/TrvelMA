/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Displays a paged tab of recently added trips.
*/

import SwiftUI
import SwiftData

/// Displays recently added trips in a paged TabView.
struct RecentTripsPageView: View {

    @Query(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\Trip.creationDate, order: .reverse)], fetchLimit: 5))
    private var trips: [Trip]

    /// The namespace used for coordinating a navigation transition.
    @Namespace private var namespace

    var body: some View {
        TabView {
            ForEach(trips) { trip in
                NavigationLink {
                    TripDetailView(trip: trip)
                        .navigationTransition(
                            .zoom(sourceID: trip.id, in: namespace))
                } label: {
                    TripImageView(trip: trip)
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading) {
                                Text("RECENTLY ADDED")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.limeGreen)

                                Text(trip.name)
                                    .font(.title)
                                    .fontWidth(.expanded)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 54)
                        }
                        .matchedTransitionSource(id: trip.id, in: namespace)
                }
                .buttonStyle(.plain)
            }
        }
        .tabViewStyle(.page)
        .containerRelativeFrame([.horizontal, .vertical]) { length, axis in
            if axis == .vertical {
                return length / 1.3
            } else {
                return length
            }
        }
    }
}

#Preview {
    NavigationStack {
        RecentTripsPageView()
    }
    .modelContainer(SampleData.previewContainer)
}
