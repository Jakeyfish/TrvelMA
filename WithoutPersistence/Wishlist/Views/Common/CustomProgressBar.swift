/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A custom progress bar.
*/

import SwiftUI

/// A custom progress bar.
struct CustomProgressBar: View {
    
    /// The progress value.
    var value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: proxy.size.height * 0.5)
                    .fill(value > 0.0 ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.tint.opacity(0.3)))
                
                Bar(value: value)
                    .fill(.tint)
                    .animation(.snappy) { content in
                        content
                            .opacity(value > 0 ? 1.0 : 0.0)
                    }
            }
        }
    }
}

/// A shape that represents the filled portion of a progress bar.
@Animatable
private struct Bar: Shape {

    /// The progress value, ranging from `0.0` (empty) to `1.0` (full).
    var value: Double

    /// Creates a path for the bar shape within the given rectangle.
    ///
    /// - Parameter rect: The rectangle in which to draw the bar.
    /// - Returns: A path representing the filled portion of the progress bar
    ///   as a rounded rectangle.
    func path(in rect: CGRect) -> Path {
        let radius = rect.height / 2.0
        let fullWidth = rect.width * value
        var result = Path()
        result.addRoundedRect(
            in: CGRect(
                x: rect.minX,
                y: rect.minY,
                width: max(rect.height, fullWidth),
                height: rect.height),
            cornerSize: CGSize(width: radius, height: radius),
            style: .circular)
        return result
    }
}
