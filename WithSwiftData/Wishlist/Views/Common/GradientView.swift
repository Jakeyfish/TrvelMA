/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
A gradient view.
*/
import SwiftUI

/// A view that displays a gradient from solid at the bottom-leading corner
/// to completely translucent at the other three corners.
struct GradientView<Style: ShapeStyle>: View {

    /// A fill style for the gradient.
    let style: Style

    var body: some View {
        Rectangle()
            .fill(style)
            .mask {
                MeshGradient(width: 2, height: 2, points: [
                    SIMD2<Float>(0.0, 0.0), SIMD2<Float>(1.0, 0.0),
                    SIMD2<Float>(0.0, 1.0), SIMD2<Float>(1.0, 1.0)
                ], colors: [
                    .clear, .clear,
                    .black, .clear
                ])
            }
    }

}

#Preview() {
    GradientView(style: .blue.opacity(0.5))
        .ignoresSafeArea()
}
