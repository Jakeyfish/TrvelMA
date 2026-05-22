/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Displays goals and achievements.
*/

import SwiftUI
import SwiftData

/// Displays goals and achievements.
struct GoalsView: View {

    @Query(filter: #Predicate<Goal> { $0.isAchieved }, sort: \Goal.dateAchieved, order: .reverse) private var achievedGoals: [Goal]
    @Query(filter: #Predicate<Goal> { !$0.isAchieved }, sort: \Goal.sortOrder) private var upcomingGoals: [Goal]

    /// Three flexible columns for the "Next milestones" grid.
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading) {

                    // Recent milestones section.
                    if !achievedGoals.isEmpty {
                        Section {
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 10) {
                                    ForEach(achievedGoals) { goal in
                                        AchievedGoalTile(goal: goal)
                                            .containerRelativeFrame(.horizontal)
                                            .clipShape(RoundedRectangle(cornerRadius: 16.0))
                                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                                content
                                                    .scaleEffect(1.0 - 0.12 * abs(phase.value))
                                                    .rotation3DEffect(Angle(degrees: 20 * phase.value), axis: (0, 1, 0))
                                            }
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollIndicators(.hidden)
                            .safeAreaPadding(40)
                            .scrollTargetBehavior(.viewAligned)
                            .scrollClipDisabled()
                        }
                    }

                    // Next milestones section.
                    if !upcomingGoals.isEmpty {
                        Section {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(upcomingGoals) { goal in
                                    GoalTile(goal: goal)
                                }
                            }
                        } header: {
                            VStack(alignment: .leading) {
                                Text("Next milestones")
                                    .font(.title3)
                                    .fontWidth(.expanded)

                                Text("Earn these awards by completing trips and activities")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.horizontal)
                    }
                    Spacer()
                }
            }
            .toolbar {
                // To customize the font of the navigation title, or add
                // other custom views, use a toolbar item with the title
                // placement.
                ToolbarItem(placement: .title) {
                    ExpandedNavigationTitle(title: "Goals")
                }
            }
            // Always add a navigation title. It's used for the
            // accessibility label when navigating back from a detail view.
            .navigationTitle("Goals")
            .toolbarTitleDisplayMode(.inline)
            // Leading-align the custom title.
            .toolbarRole(.editor)
        }
    }
}

// MARK: - Achieved Goal Tile

/// A large tile view displaying an achieved goal's badge, name, and subtitle.
private struct AchievedGoalTile: View {

    /// The goal to display.
    var goal: Goal

    var body: some View {
        VStack {
            Image(goal.badgeName)
                .resizable()
                .scaledToFit()
                .frame(width: 250, height: 250)
                .padding(.bottom, 10)

            Text(goal.name)
                .font(.title2)
                .fontWidth(.expanded)
                .multilineTextAlignment(.center)

            Text(goal.subtitle)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(.secondary.opacity(0.2), in: .rect(cornerRadius: 16))
    }
}

// MARK: - Goal Tile

/// A tile view displaying a single goal's badge, name, and progress.
private struct GoalTile: View {

    /// The goal to display.
    var goal: Goal

    var body: some View {
        VStack(spacing: 8) {
            Image(goal.badgeName)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .padding(.bottom, 8)

            Text(goal.name)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("\(min(goal.completedCount, goal.target)) of \(goal.target)")
                .font(.caption)
                .foregroundStyle(.secondary)

            CustomProgressBar(value: goal.progressValue)
                .tint(.limeGreen)
                .frame(height: 6)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(.secondary.opacity(0.2), in: .rect(cornerRadius: 16))
    }
}

#Preview {
    GoalsView()
        .modelContainer(SampleData.previewContainer)
}
