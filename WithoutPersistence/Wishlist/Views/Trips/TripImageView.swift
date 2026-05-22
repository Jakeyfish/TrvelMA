/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A view that displays an image from a URL.
*/

import SwiftUI

/// A view that displays an image from a URL.
struct TripImageView: View {

    /// The URL for the image.
    var url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                /// The rectangle shape takes all available space offered to it by superviews.
                /// The overlay builds on top of that, so the AsyncImage is constrained by the frame offered by the superview.
                /// The Image is clipped to space taken by the background color.
                Rectangle()
                    .fill(.background)
                    .overlay {
                        image.resizable()
                            .scaledToFill()
                    }
                    .clipped()
            } else if phase.error != nil {
                Image(systemName: "photo.fill")
                    .resizable()
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
    }
}

#Preview {
    TripImageView(url: Bundle.main.url(forResource: "Shore", withExtension: "jpeg")!)
}
