/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Displays a searchable list of trips and activities.
*/

import SwiftUI

/// A view that allows users to search for trips and activities.
///
/// Shows recently created trips when the search field is empty.
/// When searching, displays matching trips and activities in separate sections.
struct SearchView: View {
    
    /// The data source that provides search data.
    @Environment(DataSource.self) private var dataSource

    /// The namespace used for coordinating a navigation transition.
    @Namespace private var namespace

    var body: some View {
        @Bindable var dataSource = dataSource

        NavigationStack {
            SearchResultsListView(namespace: namespace)
                .toolbar {
                    // To customize the font of the navigation title, or add other
                    // custom views, use a toolbar item with the title placement.
                    ToolbarItem(placement: .title) {
                        ExpandedNavigationTitle(title: "查找")
                    }
                }
                // Always add a navigation title. It's used for the
                // accessibility label when navigating back from a detail
                // view.
                .navigationTitle("搜索")
                .toolbarTitleDisplayMode(.inline)
                // Leading-align the custom title.
                .toolbarRole(.editor)
                .searchable(
                    text: $dataSource.searchText,
                    prompt: "行程, 目的地或其它."
                )
                .scrollDismissesKeyboard(.immediately)
        }
    }
}

/// A view that displays the search results.
private struct SearchResultsListView: View {

    /// The data source that provides search data.
    @Environment(DataSource.self) private var dataSource

    /// The namespace used for coordinating a navigation transition.
    var namespace: Namespace.ID

    var body: some View {
        List(dataSource.searchResults) { section in
            SearchSectionView(section: section, namespace: namespace)
        }
        .overlay {
            if dataSource.searchResults.isEmpty {
                ContentUnavailableView(
                    "未找到“\(dataSource.searchText)”",
                    systemImage: "magnifyingglass",
                    description: Text("请检查拼写或尝试其他搜索。")
                )
            }
        }
        .listStyle(.plain)
    }
}

private extension DataSource {

    /// The search results, grouped into sections.
    ///
    /// When `searchText` is empty, this returns recently added trips.
    /// Otherwise, it returns matching trips and activities.
    var searchResults: [SearchSection] {
        if searchText.isEmpty {
            // Show recent trips when not searching.
            return [.recentlyCreatedTrips(Array(recentlyAddedTrips.prefix(3)))]
        } else {
            let matchingTrips = trips.values
                .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

            let matchingActivities = trips.values
                .flatMap { $0.activities.values }
                .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

            var sections: [SearchSection] = []

            if !matchingTrips.isEmpty {
                sections.append(.trips(matchingTrips))
            }

            if !matchingActivities.isEmpty {
                sections.append(.activities(matchingActivities))
            }

            return sections
        }
    }
}

/// Represents different sections that can appear in search results.
private enum SearchSection: Identifiable {
    /// Recently created trips shown when search is empty.
    case recentlyCreatedTrips([Trip])

    /// Trips matching the search query.
    case trips([Trip])

    /// Activities matching the search query.
    case activities([Activity])
}

private extension SearchSection {
    /// A unique string identifier for each search section type.
    var id: String {
        switch self {
        case .recentlyCreatedTrips: "recent"
        case .trips: "trips"
        case .activities: "activities"
        }
    }

    /// The display title for each section.
    var title: String {
        switch self {
        case .recentlyCreatedTrips: "Recently Created"
        case .trips: "Trips"
        case .activities: "活动"
        }
    }
}

/// A view that displays a search result item with a photo and name.
private struct SearchItemView: View {

    /// The name of the trip or activity.
    var name: String

    /// The photo asset name for the trip or activity.
    var photoURL: URL

    /// The unique identifier for the trip, used for navigation.
    var tripID: Trip.ID

    /// The namespace used for coordinating the matched transition source.
    var linkNamespace: Namespace.ID

    var body: some View {
        HStack(spacing: 16) {
            TripImageView(url: photoURL)
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(.rect(cornerRadius: 8))
                .matchedTransitionSource(id: tripID, in: linkNamespace)

            Text(name)
                .font(.title3)
                .fontWeight(.regular)
        }
    }
}

/// A view that displays a search section with its header and content.
private struct SearchSectionView: View {

    /// The data source that provides search data.
    @Environment(DataSource.self) private var dataSource

    /// The search section to display.
    var section: SearchSection

    /// The namespace used for coordinating a navigation transition.
    var namespace: Namespace.ID

    var body: some View {
        Section {
            switch section {
            case .recentlyCreatedTrips(let trips),
                .trips(let trips):
                ForEach(trips) { trip in
                    NavigationLink {
                        TripDetailView(trip: trip)
                            .navigationTransition(
                                .zoom(sourceID: trip.id, in: namespace))
                    } label: {
                        SearchItemView(
                            name: trip.name,
                            photoURL: trip.photoURL,
                            tripID: trip.id,
                            linkNamespace: namespace
                        )
                    }
                }
            case .activities(let activities):
                ForEach(activities) { activity in
                    NavigationLink {
                        TripDetailView(
                            trip: dataSource.trip(containing: activity.id)!)
                    } label: {
                        Text(activity.name)
                            .font(.title3)
                            .fontWeight(.regular)
                    }
                }
            }
        } header: {
            Text(section.title)
                .font(.title3)
                .fontWeight(.semibold)
                .fontWidth(.expanded)
                .foregroundStyle(.primary)
        }
    }
}

#Preview {
    @Previewable @State var dataSource = DataSource()

    SearchView()
        .environment(dataSource)
}
