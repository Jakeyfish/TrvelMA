/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Displays goals and achievements.
*/

import SwiftUI

/// Displays goals and achievements.
struct GoalsView: View {

    /// The data source providing goals and achievement data.
    @Environment(DataSource.self) private var dataSource

    /// Three flexible columns for the "下一个里程碑" grid.
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
                                    GoalTile(goal: goal, completedCount: dataSource.completedCount(for: goal.kind))
                                }
                            }
                        } header: {
                            VStack(alignment: .leading) {
                                Text("下一个里程碑")
                                    .font(.title3)
                                    .fontWidth(.expanded)

                                Text("完成行程和活动即可获得奖励")
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
                    ExpandedNavigationTitle(title: "目标")
                }
            }
            // Always add a navigation title. It's used for the
            // accessibility label when navigating back from a detail view.
            .navigationTitle("目标")
            .toolbarTitleDisplayMode(.inline)
            // Leading-align the custom title.
            .toolbarRole(.editor)
        }
    }
}

private extension GoalsView {

    /// The achieved goals, sorted by achievement date.
    var achievedGoals: [Goal] {
        dataSource.goals
            .filter { dataSource.dateAchieved(for: $0) != nil }
            .sorted { lhs, rhs in
                dataSource.dateAchieved(for: lhs)! > dataSource.dateAchieved(for: rhs)!
            }
    }

    /// All goals that have not yet been achieved.
    var upcomingGoals: [Goal] {
        dataSource.goals.filter { dataSource.dateAchieved(for: $0) == nil }
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

            Text(LocalizedStringKey(goal.name))
                .font(.title2)
                .fontWidth(.expanded)
                .multilineTextAlignment(.center)

            Text(goal.localizedSubtitle)
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

    /// The current completed count for this goal's kind.
    var completedCount: Int

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

            HStack(spacing: 3) {
                Text("\(min(completedCount, goal.target))")
                Text("共")
                Text("\(goal.target)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            CustomProgressBar(value: goal.progress(for: completedCount))
                .tint(Color("LimeGreen"))
                .frame(height: 6)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(.secondary.opacity(0.2), in: .rect(cornerRadius: 16))
    }
}

// MARK: - Goal subtitle

private extension Goal {

    var localizedSubtitle: LocalizedStringKey {
        switch kind {
        case .tripsCompleted:
            if target == 1 {
                "完成首次行程即可获得此奖励。"
            } else {
                "完成 \(target) 次行程即可获得此奖励。"
            }
        case .activitiesCompleted:
            if target == 1 {
                "完成首个行程活动即可获得此奖励。"
            } else {
                "完成 \(target) 个行程活动即可获得此奖励。"
            }
        case .collectionTripsCompleted:
            if target == 1 {
                "完成一次季节主题行程即可获得此奖励。"
            } else {
                "完成 \(target) 次季节主题行程即可获得此奖励。"
            }
        }
    }
}

// MARK: - Ordinal formatting

private extension Int {
    
    /// Returns the ordinal string representation of this integer (e.g., "1st", "2nd", "3rd", "5th").
    var ordinal: String {
        Self.ordinalFormatter.string(from: self as NSNumber) ?? "\(self)"
    }

    /// A formatter for converting integers to ordinal strings.
    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()
}

#Preview {
    @Previewable @State var dataSource = DataSource()

    GoalsView()
        .environment(dataSource)
}
