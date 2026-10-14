/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Displays a paged tab of recently added trips.
*/

import SwiftUI

/// Displays recently added trips in a paged TabView.
struct RecentTripsPageView: View {

    @Environment(DataSource.self) private var dataSource

    /// The namespace used for coordinating a navigation transition.
    @Namespace private var namespace

    var body: some View {
        TabView {
            ForEach(dataSource.recentlyAddedTrips) { trip in
                NavigationLink {
                    TripDetailView(trip: trip)
                        .navigationTransition(
                            .zoom(sourceID: trip.id, in: namespace))
                } label: {
                    TripImageView(url: trip.photoURL)
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading) {
                                Text("最近添加")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color("LimeGreen"))

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
    @Previewable @State var dataSource = DataSource()

    NavigationStack {
        RecentTripsPageView()
            .environment(dataSource)
    }
}
