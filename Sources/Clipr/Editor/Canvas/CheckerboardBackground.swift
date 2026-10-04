import SwiftUI

/// The light/grey checkerboard image editors use to show transparent pixels. Drawn behind the
/// canvas so space added by expanding past the image reads as transparent rather than blending
/// into the editor background.
struct CheckerboardBackground: View {
    /// Side of one square in this view's own coordinates. Callers inside a `scaleEffect` divide
    /// by the scale so squares stay the same on-screen size at any zoom.
    var squareSize: CGFloat = 8

    private static let light = Color(white: 0.92)
    private static let dark = Color(white: 0.78)

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.light))
            let side = max(squareSize, 1)
            let cols = Int((size.width / side).rounded(.up))
            let rows = Int((size.height / side).rounded(.up))
            var dark = Path()
            for row in 0..<rows {
                for col in stride(from: row % 2, to: cols, by: 2) {
                    dark.addRect(CGRect(x: CGFloat(col) * side, y: CGFloat(row) * side, width: side, height: side))
                }
            }
            context.fill(dark, with: .color(Self.dark))
        }
        .allowsHitTesting(false)
    }
}
