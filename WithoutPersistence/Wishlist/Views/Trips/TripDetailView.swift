/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Displays detailed information about a trip including activities and notes.
*/

import SwiftUI

/// Displays detailed information about a trip including activities and notes.
struct TripDetailView: View {

    /// The data source for updating goal achievements.
    @Environment(DataSource.self) private var dataSource

    /// The current sorting option for activities.
    @AppStorage("ActivitiesSortedBy") var sortOption = SortOption.title

    /// The model which manages the trip's editing state.
    @State private var model: TripEditModel

    /// Initializes the trip detail view with the specified trip.
    ///
    /// - Parameter trip: The trip to display and manage in the detail view.
    init(trip: Trip) {
        _model = State(initialValue: TripEditModel(trip: trip))
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                TripImageView(url: model.photoURL)
                    .scaledToFill()
                    .containerRelativeFrame(.horizontal)
                    .frame(height: 510)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        ActivityProgressView(completionValue: model.progressValue)
                    }

                ActivitySection(sortOption: $sortOption)
            }
        }
        .contentMargins(.bottom, 30, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .toolbar {
            // To customize the font of the navigation title, or add
            // other custom views, while pinnning those views to the top
            // of the display, use a toolbar item with the title
            // placement.
            ToolbarItem(placement: .largeTitle) {
                HStack {
                    Text(model.name)
                        .font(.headline)
                        .fontWeight(.medium)
                        .fontWidth(.expanded)
                        .fixedSize()
                    Spacer()
                }
            }

            ToolbarItem(placement: .primaryAction) {
                if model.isEditing {
                    Button(role: .confirm) {
                        model.isEditing.toggle()
                    }
                } else {
                    Button("编辑") {
                        model.isEditing.toggle()
                    }
                }
            }
        }
        .onChange(of: model.isEditing) {
            // When exiting edit mode, remove any activities with empty names.
            if !model.isEditing {
                model.activities = model.activities.filter { !$0.name.isEmpty }
            }
        }
        .onDisappear {
            // Save any changes to activities when navigating away from the detail view.
            model.saveActivities(dataSource: dataSource)
        }
        .environment(model)
        .ignoresSafeArea(edges: .top)
        .toolbarTitleDisplayMode(.inline)
        // Always add a navigation title. It's used for the accessibility
        // label when navigating back from a detail view.
        .navigationTitle(model.name)
        .toolbarRole(.editor)
    }
}

/// A view that displays the activity completion progress.
private struct ActivityProgressView: View {
    /// The width of the progress bar, scaled relative to the body text size.
    @ScaledMetric(relativeTo: .body) private var barWidth = 150

    /// The height of the progress bar, scaled relative to the body text size.
    @ScaledMetric(relativeTo: .body) private var barHeight = 10

    /// The completion progress value as a value from 0.0 to 1.0.
    var completionValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(
                completionValue,
                format: .percent.precision(.fractionLength(0))
            )
            .font(.title)
            .fontWidth(.expanded)
            .fontWeight(.regular)
            .contentTransition(.numericText())
            .opacity(completionValue > 0 ? 1.0 : 0.0)
            .animation(.smooth, value: completionValue)

            CustomProgressBar(value: completionValue)
                .tint(Color("LimeGreen"))
                .frame(width: barWidth, height: barHeight)

            Text("行程活动")
                .font(.footnote.smallCaps())
                .fontWidth(.condensed)
                .foregroundStyle(.secondary)
        }
        .animation(.bouncy, value: completionValue)
        .padding()
        .background {
            // Add a subtle background to make the text stand out.
            GradientView(style: .ultraThinMaterial)
        }
    }
}

#Preview {
    @Previewable @State var dataSource = DataSource()
    @Previewable @State var trip = Trip(
        name: "Summer Adventure",
        collection: .summerVibes,
        photoURL: Bundle.main.url(forResource: "Shore", withExtension: "jpeg")!,
        activities: [
            Activity(name: "Beach Picnic"),
            Activity(name: "Surfing Lessons"),
            Activity(name: "Snorkeling Adventure")
        ]
    )

    NavigationStack {
        TripDetailView(trip: trip)
    }
    .environment(dataSource)
}
