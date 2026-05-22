/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A reusable section component that displays a list of trips.
*/

import SwiftUI

/// A view that displays a trip collection with a horizontally scrolling list of trip cards.
struct TripCollectionView: View {

    /// The data source containing trips.
    @Environment(DataSource.self) private var dataSource

    /// The trip collection to display.
    var tripCollection: TripCollection

    /// The size of the trip cards.
    var cardSize: TripCard.Size

    /// The namespace used for coordinating a navigation transition.
    var namespace: Namespace.ID

    var body: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(dataSource.trips(in: tripCollection)) { trip in
                        NavigationLink {
                            TripDetailView(trip: trip)
                                .navigationTransition(
                                    .zoom(sourceID: trip.id, in: namespace))
                        } label: {
                            TripCard(trip: trip, size: cardSize)
                                .matchedTransitionSource(id: trip.id, in: namespace)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .scrollIndicators(.hidden, axes: .horizontal)
            .padding(.bottom, 30)
        } header: {
            VStack(alignment: .leading, spacing: 0) {
                Text(tripCollection.name)
                    .font(.title3)
                    .fontWidth(.expanded)

                if let summary = tripCollection.summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .lineLimit(2)
        }
        .padding(.horizontal, 16)
    }
}

// MARK: Trip card view

/// A card view that displays a trip's photo and name.
struct TripCard: View {

    /// The trip to display.
    var trip: Trip
    
    /// The size of the card.
    var size: Size

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TripImageView(url: trip.photoURL)
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipShape(.rect(cornerRadius: 16))
                .overlay(alignment: .bottomLeading) {
                    if !trip.activities.isEmpty {
                        Text("^[\(trip.activities.count) ACTIVITIES](inflect: true)")
                            .font(.footnote)
                            .fontWidth(.condensed)
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(.regularMaterial, in: .rect(cornerRadius: 8))
                            .padding([.leading, .bottom], 8)
                    }
                }

            VStack(alignment: .leading, spacing: 0) {
                Text(trip.name)
                    .font(.body)

                if let subtitle = trip.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .lineLimit(2)
        }
        .frame(width: size.width)
    }
}

// MARK: - Card size

extension TripCard {

    /// The available sizes for trip cards.
    enum Size {

        /// A compact card.
        case compact

        /// An expanded card.
        case expanded
    }
}

private extension TripCard.Size {

    /// The width of the card for this size.
    var width: CGFloat {
        switch self {
        case .compact: 180
        case .expanded: 325
        }
    }
    
    /// The height of the card for this size.
    var height: CGFloat {
        switch self {
        case .compact, .expanded: 260
        }
    }
}

#Preview {
    @Previewable @Namespace var namespace
    @Previewable @State var dataSource = DataSource()

    NavigationStack {
        VStack(spacing: 30) {
            TripCollectionView(tripCollection: .summerVibes, cardSize: .expanded, namespace: namespace)
        }
    }
    .environment(dataSource)
}
