import SwiftUI

/// Renders an arrow as a stroked shaft plus a filled triangular head, using the exact same
/// geometry (`arrowGeometry`, in `ArrowGeometry.swift`) as the final flattened render — so what
/// the user sees while dragging matches what gets saved.
struct ArrowView: View {
    let start: CGPoint
    let end: CGPoint
    let strokeWidth: CGFloat
    let color: Color

    var body: some View {
        let geo = arrowGeometry(from: start, to: end, strokeWidth: strokeWidth)
        ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: geo.shaftEnd)
            }
            .stroke(color, lineWidth: strokeWidth)
            Path { path in
                path.move(to: geo.tip)
                path.addLine(to: geo.corner1)
                path.addLine(to: geo.corner2)
                path.closeSubpath()
            }
            .fill(color)
        }
    }
}
