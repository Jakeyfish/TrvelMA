/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A view that displays an image from data.
*/

import SwiftUI
import UniformTypeIdentifiers

/// A view that displays an image from data.
struct TripImageView: View {

    /// The image data to display.
    var data: Data

    @State private var image: Image?

    init(trip: Trip) {
        self.data = trip.thumbnailData ?? trip.photo.data
    }

    init(data: Data) {
        self.data = data
    }

    var body: some View {
        Group {
            if let image {
                /// The rectangle shape takes all available space offered to it by superviews.
                /// The overlay builds on top of that, so the Image is constrained by the frame offered by the superview.
                /// The Image is clipped to space taken by the background color.
                Rectangle()
                    .fill(.background)
                    .overlay {
                        image.resizable()
                            .scaledToFill()
                    }
                    .clipped()
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .task(id: data) {
            do {
                image = try await Image(importing: data, contentType: .image)
            } catch {
                image = Image(systemName: "photo.fill")
            }
        }
    }
}

#Preview {
    TripImageView(data: TripImage(name: "Shore").data)
}
