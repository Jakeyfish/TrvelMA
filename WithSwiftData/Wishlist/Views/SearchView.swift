/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Displays a searchable list of trips and activities.
*/

import SwiftUI
import SwiftData

/// A view that allows people to search for trips and activities.
///
/// Shows recently created trips when the search field is empty.
/// When searching, displays matching trips and activities in separate sections.
struct SearchView: View {
    
    /// The current search query text.
    @State private var searchText = ""

    /// The namespace used for coordinating a navigation transition.
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            SearchResultsListView(searchText: searchText, namespace: namespace)
                .toolbar {
                    // To customize the font of the navigation title, or add other
                    // custom views, use a toolbar item with the title placement.
                    ToolbarItem(placement: .title) {
                        ExpandedNavigationTitle(title: "Search")
                    }
                }
                // Always add a navigation title. It's used for the
                // accessibility label when navigating back from a detail
                // view.
                .navigationTitle("Search")
                .toolbarTitleDisplayMode(.inline)
                // Leading-align the custom title.
                .toolbarRole(.editor)
                .searchable(
                    text: $searchText,
                    prompt: "Trips, Destinations and More."
                )
                .scrollDismissesKeyboard(.immediately)
        }
    }
}

/// A view that displays the search results.
private struct SearchResultsListView: View {

    @Query(sort: \Trip.name) private var trips: [Trip]
    @Query(sort: \Activity.name) private var activities: [Activity]

    /// The current search text.
    var searchText: String

    /// The namespace used for coordinating a navigation transition.
    var namespace: Namespace.ID

    init(searchText: String, namespace: Namespace.ID) {
        self.searchText = searchText
        self.namespace = namespace

        if searchText.isEmpty {
            _trips = Query(FetchDescriptor(sortBy: [SortDescriptor(\Trip.creationDate, order: .reverse)], fetchLimit: 3))
            _activities = Query(filter: #Predicate<Activity> { _ in false })
        } else {
            let tripSearchPredicate = #Predicate<Trip> { $0.name.localizedStandardContains(searchText) }
            _trips = Query(filter: tripSearchPredicate, sort: \Trip.name)
            let activitySearchPredicate = #Predicate<Activity> { $0.trip != nil && $0.name.localizedStandardContains(searchText) }
            _activities = Query(filter: activitySearchPredicate, sort: \Activity.name)
        }
    }

    var body: some View {
        List {
            if !trips.isEmpty {
                TripSearchSectionView(trips: trips, namespace: namespace, title: searchText.isEmpty ? "Recent Trips" : "Trips")
            }

            if !activities.isEmpty {
                ActivitySearchSectionView(activities: activities)
            }
        }
        .overlay {
            if trips.isEmpty && activities.isEmpty {
                ContentUnavailableView(
                    "No results for “\(searchText)”",
                    systemImage: "magnifyingglass",
                    description: Text("Check spelling or try a new search.")
                )
            }
        }
        .listStyle(.plain)
    }
}

/// A view that displays a search result item with a photo and name.
private struct SearchItemView: View {

    /// The name of the trip or activity.
    var name: String

    /// The photo asset name for the trip or activity.
    var photoData: Data?

    /// The unique identifier for the trip, used for navigation.
    var tripID: Trip.ID

    /// The namespace used for coordinating the matched transition source.
    var linkNamespace: Namespace.ID

    var body: some View {
        HStack(spacing: 16) {
            if let photoData {
                TripImageView(data: photoData)
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(.rect(cornerRadius: 8))
                    .matchedTransitionSource(id: tripID, in: linkNamespace)
            }

            Text(name)
                .font(.title3)
                .fontWeight(.regular)
        }
    }
}

/// A view that displays a search section with its header and content.
private struct TripSearchSectionView: View {

    /// The trips to display.
    var trips: [Trip] = []

    /// The namespace used for coordinating a navigation transition.
    var namespace: Namespace.ID

    let title: String

    var body: some View {
        Section {
            ForEach(trips) { trip in
                NavigationLink {
                    TripDetailView(trip: trip)
                        .navigationTransition(
                            .zoom(sourceID: trip.id, in: namespace))
                } label: {
                    SearchItemView(
                        name: trip.name,
                        photoData: trip.thumbnailData,
                        tripID: trip.id,
                        linkNamespace: namespace
                    )
                }
            }
        } header: {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
                .fontWidth(.expanded)
                .foregroundStyle(.white)
        }
    }
}

private struct ActivitySearchSectionView: View {
    /// The activities to display.
    var activities: [Activity] = []

    var body: some View {
        Section {
            ForEach(activities) { activity in
                if let trip = activity.trip {
                    NavigationLink {
                        TripDetailView(trip: trip)
                    } label: {
                        Text(activity.name)
                            .font(.title3)
                            .fontWeight(.regular)
                    }
                }
            }
        } header: {
            Text("Activities")
                .font(.title3)
                .fontWeight(.semibold)
                .fontWidth(.expanded)
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    SearchView()
        .modelContainer(SampleData.previewContainer)
}
