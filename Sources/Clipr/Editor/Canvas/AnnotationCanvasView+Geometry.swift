import CoreGraphics
import Cocoa

/// Small geometry helpers shared by the gesture handlers, live preview, and resize handles. See
/// `AnnotationCanvasView.swift`'s header for how this file relates to the rest of the type.
extension AnnotationCanvasView {
    func rectBetween(_ start: CGPoint, _ current: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y)
        )
    }

    /// With Shift held, the usual drawing constraints: boxes, ellipses, highlights and redactions
    /// become squares/circles, and arrows snap to the nearest 45°. Otherwise `end` unchanged.
    func constrained(_ end: CGPoint, from start: CGPoint) -> CGPoint {
        guard NSEvent.modifierFlags.contains(.shift) else { return end }
        let dx = end.x - start.x, dy = end.y - start.y
        switch selectedTool {
        case .arrow:
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        case .rectangle, .ellipse, .highlighter, .blur:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        default:
            return end
        }
    }
}
