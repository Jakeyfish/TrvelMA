/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The trip activities section.
*/

import SwiftUI
import SwiftData

/// The trip activities section.
struct ActivitySection: View {

    /// The current sorting option for activities.
    @Binding var sortOption: SortOption

    /// Whether the detail view is in editing mode.
    @Binding var isEditing: Bool

    var trip: Trip

    var body: some View {
        Section {
            ActivityList(trip: trip, sortOption: sortOption, isEditing: $isEditing)
        } header: {
            ActivitiesHeader(sortOption: $sortOption, isEditing: isEditing)
        }
        .padding(.horizontal)
    }
}

/// A view that displays the header for the activities section.
private struct ActivitiesHeader: View {

    /// The current sorting option for activities.
    @Binding var sortOption: SortOption

    /// Whether the detail view is in editing mode.
    var isEditing: Bool

    var body: some View {
        HStack {
            Text("Activities")
                .font(.title3)
                .fontWidth(.expanded)

            Spacer()

            Menu("Sort", systemImage: "arrow.up.arrow.down") {
                Picker("Sort By", selection: $sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Text(option.title)
                            .tag(option)
                    }
                }
                .pickerStyle(.inline)
            }
            .disabled(isEditing)
        }
    }
}

/// A view that displays a list of activities.
private struct ActivityList: View {

    @Environment(\.modelContext) private var modelContext

    /// The activities being displayed.
    @Query private var activities: [Activity]

    var trip: Trip

    /// Whether the detail view is in editing mode.
    @Binding var isEditing: Bool

    init(trip: Trip, sortOption: SortOption, isEditing: Binding<Bool>) {
        self.trip = trip
        _isEditing = isEditing
        let tripID = trip.persistentModelID
        let predicate = #Predicate<Activity> { $0.trip?.persistentModelID == tripID }
        _activities = Query(filter: predicate, sort: sortOption.sortDescriptors)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            addActivityView

            ForEach(activities) { activity in
                ActivityItemView(
                    activity: activity,
                    isLast: activity.id == activities.last?.id,
                    isEditing: isEditing
                )
            }
        }
    }
}

extension ActivityList {

    /// A button to add an activity when the list is empty.
    private var addActivityView: some View {
        Button {
            let activity = Activity(name: "")
            activity.trip = trip
            trip.activities.append(activity)
            isEditing = true
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 17) {
                Image(systemName: "plus")

                VStack(alignment: .leading) {
                    Text("Add an Activity")
                        .font(.body)

                    Divider()
                }
                .contentShape(.rect)
            }
            .imageScale(.large)
        }
        .buttonStyle(.plain)
    }
}

/// A view that displays a single activity item.
private struct ActivityItemView: View {

    @Query(filter: #Predicate<TripGoal> { !$0.isAchieved }) private var upcomingTripGoals: [TripGoal]
    @Query(filter: #Predicate<ActivityGoal> { !$0.isAchieved }) private var upcomingActivityGoals: [ActivityGoal]

    /// The activity to display.
    var activity: Activity

    /// Whether this is the last item in the list.
    var isLast: Bool

    /// Whether the detail view is in editing mode.
    var isEditing: Bool

    /// Controls the delete confirmation dialog.
    @State private var isShowingDeleteConfirmation = false

    /// Used to match the item name text when animating in and out of editing mode.
    @Namespace private var editingTransition

    @Environment(\.modelContext) private var modelContext

    @State private var updateError: Error?

    init(activity: Activity, isLast: Bool, isEditing: Bool) {
        activity.token = withContinuousObservation(options: .didSet) { event in
            _ = activity.name
            _ = activity.isComplete

            if event.matches(\Activity.name) {
                activity.dateEdited = .now
            }

            if event.matches(\Activity.isComplete) {
                activity.dateEdited = .now
                activity.trip?.isComplete = activity.trip?.activities.isEmpty == false
                && activity.trip?.activities.allSatisfy { $0.isComplete } == true
            }
        }
        self.activity = activity
        self.isLast = isLast
        self.isEditing = isEditing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 17) {
            // The item can display in one of two modes: editing or not editing.
            // In editing mode, people can tap a button on the trailing edge to
            // delete the item. People can edit activity text by tapping the
            // activity name. On the other hand, when not editing, people can
            // tap anywhere in the row to toggle the item's completion status.
            Group {
                if isEditing {
                    rowContentWhenEditing
                } else {
                    rowContentWhenNotEditing
                }
            }
            // Animates the showing and hiding of controls when switching modes:
            .transition(.opacity.animation(.snappy))
            // Animates the position of the activity's name when switching modes:
            .animation(.snappy, value: isEditing)
        }
        .onDisappear {
            do {
                try updateGoalAchievements()
            } catch {
                updateError = error
            }
        }
        .alert(error: $updateError) {
            // Customize the error message and actions here.
        }
    }

    @ViewBuilder
    private var rowContentWhenEditing: some View {
        // A matched-geometry effect associates the activity name in the
        // editing and not-editing modes so that it smoothly moves when
        // switching modes.
        activityNameStack
            .matchedGeometryEffect(id: "activityName", in: editingTransition)

        Button("Delete", systemImage: "minus.circle", role: .destructive) {
                isShowingDeleteConfirmation = true
        }
        .symbolVariant(.fill)
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .confirmationDialog("Delete Activity", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    activity.trip?.isComplete = activity.trip?.activities.isEmpty == false
                    && activity.trip?.activities.allSatisfy { $0.id == activity.id || $0.isComplete } == true
                    activity.trip?.activities.removeAll { $0.id == activity.id }
                    modelContext.delete(activity)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this activity?")
        }
    }

    @ViewBuilder
    private var rowContentWhenNotEditing: some View {
        Button {
            activity.isComplete.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 17) {
                Image(systemName: activity.isComplete ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(activity.isComplete ? Color.accentColor : .gray)
                .contentTransition(.symbolEffect)
                .animation(.snappy, value: activity.isComplete)
                .imageScale(.large)

                // A matched-geometry effect associates the activity name in the
                // editing and not-editing modes so that it smoothly moves when
                // switching modes.
                activityNameStack
                    .matchedGeometryEffect(id: "activityName", in: editingTransition)
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var activityNameStack: some View {
        VStack {
            // Can only edit the name in edit mode, but the name should still be
            // tappable to toggle the completion status when not editing. To keep
            // layout in both modes, a ZStack holds both the editable text field and
            // a plain text, hiding whichever isn't currently applicable.
            ZStack(alignment: .leadingFirstTextBaseline) {
                ActivityTextField(activity: activity)
                    .opacity(isEditing ? 1 : 0)
                Text(activity.name)
                    .opacity(isEditing ? 0 : 1)
            }
            Divider()
                .opacity(isLast ? 0 : 1)
        }
    }

    private func updateGoalAchievements() throws {
        let completedActivitiesCount = try modelContext.fetchCount(FetchDescriptor<Activity>(predicate: #Predicate { $0.isComplete }))

        for goal in upcomingActivityGoals {
            goal.completedCount = completedActivitiesCount

            if goal.completedCount >= goal.target {
                goal.isAchieved = true
                goal.dateAchieved = .now
                goal.tripAchieved = activity.trip
            }
        }

        for goal in upcomingTripGoals {
            var predicate = #Predicate<Trip> { $0.isComplete }

            if let collection = goal.collection {
                predicate = #Predicate { trip in
                    predicate.evaluate(trip) && trip.collection == collection
                }
            }

            let completedTripsCount = try modelContext.fetchCount(FetchDescriptor<Trip>(predicate: predicate))
            goal.completedCount = completedTripsCount

            if goal.completedCount >= goal.target {
                goal.isAchieved = true
                goal.dateAchieved = .now
            }
        }
    }
}

/// A text field for entering activity names.
private struct ActivityTextField: View {

    @Environment(\.modelContext) private var modelContext

    /// The activity to display.
    var activity: Activity

    @State private var text: String

    @FocusState private var isFocused: Bool

    init(activity: Activity) {
        self.activity = activity
        self.text = activity.name
    }

    var body: some View {
        TextField(
            "Enter activity name",
            text: $text
        )
        .textFieldStyle(.plain)
        .focused($isFocused)
        .onChange(of: isFocused) {
            if !isFocused && text != activity.name {
                activity.name = text
                activity.dateEdited = .now
                modelContext.insert(activity)
            }
        }
    }
}

extension Bool: @retroactive Comparable {
    public static func <(lhs: Self, rhs: Self) -> Bool {
        !lhs && rhs
    }
}

#Preview {
    @Previewable @State var sortOption = SortOption.dateCreated
    @Previewable @State var isEditing = false
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
        ActivitySection(sortOption: $sortOption, isEditing: $isEditing, trip: trip)
    }
    .modelContainer(SampleData.previewContainer)
}
