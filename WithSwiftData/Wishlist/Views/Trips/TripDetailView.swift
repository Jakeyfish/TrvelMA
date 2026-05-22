/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Displays detailed information about a trip including activities and notes.
*/

import SwiftUI
import SwiftData

/// Displays detailed information about a trip including activities and notes.
struct TripDetailView: View {

    /// The model context for saving changes.
    @Environment(\.modelContext) private var modelContext

    /// The current sorting option for activities.
    @AppStorage("ActivitiesSortedBy") var sortOption = SortOption.title

    /// The trip to display and manage.
    var trip: Trip

    /// Whether the detail view is in editing mode.
    @State private var isEditing = false

    init(trip: Trip) {
        self.trip = trip
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                TripImageView(data: trip.photo.data)
                    .scaledToFill()
                    .containerRelativeFrame(.horizontal)
                    .frame(height: 510)
                    .clipped()
                    .overlay(alignment: .bottomLeading) {
                        ActivityProgressView(completionValue: trip.progressValue)
                    }

                ActivitySection(sortOption: $sortOption, isEditing: $isEditing, trip: trip)
            }
        }
        .contentMargins(.bottom, 30, for: .scrollContent)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .toolbar {
            // To customize the font of the navigation title, or add
            // other custom views, while pinning those views to the top
            // of the display, use a toolbar item with the title
            // placement.
            ToolbarItem(placement: .largeTitle) {
                HStack {
                    Text(trip.name)
                        .font(.headline)
                        .fontWeight(.medium)
                        .fontWidth(.expanded)
                        .fixedSize()
                    Spacer()
                }
            }

            ToolbarItem(placement: .primaryAction) {
                if isEditing {
                    Button(role: .confirm) {
                        isEditing.toggle()
                    }
                } else {
                    Button("Edit") {
                        isEditing.toggle()
                    }
                }
            }
        }
        .onChange(of: isEditing, initial: true) {
            // When exiting edit mode, remove any activities with empty names.
            if !isEditing {
                for activity in trip.activities where activity.name.isEmpty {
                    modelContext.delete(activity)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbarTitleDisplayMode(.inline)
        // Always add a navigation title. It's used for the accessibility
        // label when navigating back from a detail view.
        .navigationTitle(trip.name)
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
                .tint(.limeGreen)
                .frame(width: barWidth, height: barHeight)

            Text("Trip Activities")
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
    @Previewable @State var trip = Trip(
        name: "Summer Adventure",
        collection: .summerVibes,
        photo: TripImage(name: "Shore"),
        activities: [
            Activity(name: "Beach Picnic"),
            Activity(name: "Surfing Lessons"),
            Activity(name: "Snorkeling Adventure")
        ]
    )

    NavigationStack {
        TripDetailView(trip: trip)
    }
    .modelContainer(SampleData.previewContainer)
}
