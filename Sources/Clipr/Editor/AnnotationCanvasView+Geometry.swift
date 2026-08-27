import CoreGraphics

/// Small geometry helper shared by the gesture handlers, live preview, and resize handles. See
/// `AnnotationCanvasView.swift`'s header for how this file relates to the rest of the type.
extension AnnotationCanvasView {
    func rectBetween(_ start: CGPoint, _ current: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y)
        )
    }
}
