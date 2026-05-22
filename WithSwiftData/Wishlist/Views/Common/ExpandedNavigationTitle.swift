/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A large title in an expanded font.
*/

import SwiftUI

/// A large title in an expanded font.
struct ExpandedNavigationTitle: View {
    /// The title to display.
    var title: LocalizedStringKey

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 34, weight: .medium))
                .fontWidth(.expanded)
                .bold()
                .fixedSize()
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        Text("Hello world")
            .toolbar {
                ToolbarItem(placement: .largeTitle) {
                    ExpandedNavigationTitle(title: "Title")
                }
            }
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationTitle("Title")
    }
}
