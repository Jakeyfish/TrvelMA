/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
The trip activities section.
*/

import SwiftUI

/// The trip activities section.
struct ActivitySection: View {

    /// The current sorting option for activities.
    @Binding var sortOption: SortOption

    var body: some View {
        Section {
            ActivityList()
        } header: {
            ActivitiesHeader(sortOption: $sortOption)
        }
        .padding(.horizontal)
    }
}

/// A view that displays the header for the activities section.
private struct ActivitiesHeader: View {

    /// The model which manages the trip's editing state.
    @Environment(TripEditModel.self) private var model

    /// The current sorting option for activities.
    @Binding var sortOption: SortOption

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
            .disabled(model.isEditing)
        }
        .onChange(of: sortOption, initial: true) {
            model.activities.sort(by: sortOption)
        }
    }
}

/// A view that displays a list of activities.
private struct ActivityList: View {

    /// The model which manages the trip's editing state.
    @Environment(TripEditModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            addActivityView

            ForEach(model.activities) { activity in
                ActivityItemView(
                    activity: activity,
                    isLast: activity.id == model.activities.last?.id
                )
            }
        }
    }
}

extension ActivityList {

    /// A button to add an activity when the list is empty.
    private var addActivityView: some View {
        Button {
            model.addNewActivity()
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

    /// The data source for updating goal achievements.
    @Environment(DataSource.self) private var dataSource

    /// The model which manages the trip's editing state.
    @Environment(TripEditModel.self) private var model

    /// The activity to display.
    var activity: Activity

    /// Whether this is the last item in the list.
    var isLast: Bool

    /// Controls the delete confirmation dialog.
    @State private var isShowingDeleteConfirmation = false

    /// Used to match the item name text when animating in and out of editing mode.
    @Namespace private var editingTransition

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 17) {
            // The item can display in one of two modes: editing or not editing.
            // In editing mode, people can tap a button on the trailing edge to
            // delete the item. People can edit activity text by tapping the
            // activity name. On the other hand, when not editing, people can
            // tap anywhere in the row to toggle the item's completion status.
            Group {
                if model.isEditing {
                    rowContentWhenEditing
                } else {
                    rowContentWhenNotEditing
                }
            }
            // Animates the showing and hiding of controls when switching modes:
            .transition(.opacity.animation(.snappy))
            // Animates the position of the activity's name when switching modes:
            .animation(.snappy, value: model.isEditing)
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
                    model.removeActivity(activity)
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
                ActivityTextField(model: model, activity: activity)
                    .opacity(model.isEditing ? 1 : 0)
                Text(activity.name)
                    .opacity(model.isEditing ? 0 : 1)
            }
            Divider()
                .opacity(isLast ? 0 : 1)
        }
    }
}

/// A text field for entering activity names.
private struct ActivityTextField: View {

    /// The model which manages the trip's editing state.
    var model: TripEditModel

    /// The activity to display.
    @Bindable var activity: Activity

    var body: some View {
        TextField(
            "Enter activity name",
            text: $activity.name
        )
        .textFieldStyle(.plain)
        .onSubmit {
            model.addNewActivity()
        }
    }
}

#Preview {
    @Previewable @State var dataSource = DataSource()
    @Previewable @State var sortOption = SortOption.dateCreated
    @Previewable @State var editModel = TripEditModel(
        trip: Trip(
            name: "Summer Adventure",
            collection: .summerVibes,
            photoURL: Bundle.main.url(forResource: "Shore", withExtension: "jpeg")!,
            activities: [
                Activity(name: "Beach Picnic"),
                Activity(name: "Surfing Lessons"),
                Activity(name: "Snorkeling Adventure")
            ]
        )
    )

    NavigationStack {
        ActivitySection(sortOption: $sortOption)
    }
    .environment(dataSource)
    .environment(editModel)
}
