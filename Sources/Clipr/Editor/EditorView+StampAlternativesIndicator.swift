import SwiftUI

extension EditorView {
    /// The corner wedge marking a toolbar slot that has alternatives behind it: a right triangle
    /// filling the bottom-right, pointing into the corner.
    struct StampAlternativesIndicator: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}
