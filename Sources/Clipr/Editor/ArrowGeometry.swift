import CoreGraphics

struct ArrowGeometry {
    /// Where the shaft line should stop — short of `tip`, at the head triangle's base — so a
    /// thick shaft stroke doesn't poke past the triangle's sides and blunt the point.
    let shaftEnd: CGPoint
    let tip: CGPoint
    let corner1: CGPoint
    let corner2: CGPoint
}

/// Shared by `AnnotationRenderer.drawArrow` (the final flattened render) and
/// `AnnotationCanvasView.ArrowView` (the live editor preview) so both scale the arrowhead
/// identically — a head sized only for the thinnest stroke preset gets visually swallowed by a
/// thick one, reading as a line that just stops rather than a clear arrow.
func arrowHeadLength(for strokeWidth: CGFloat) -> CGFloat {
    max(14, strokeWidth * 3.5)
}

/// Shared arrow geometry: a shaft segment plus a filled triangular head. Kept separate from
/// drawing so both the CoreGraphics renderer and the SwiftUI live preview compute the exact same
/// shape.
func arrowGeometry(from start: CGPoint, to end: CGPoint, strokeWidth: CGFloat) -> ArrowGeometry {
    let headLength = arrowHeadLength(for: strokeWidth)
    let dx = end.x - start.x, dy = end.y - start.y
    let length = max(hypot(dx, dy), 0.0001)
    let ux = dx / length, uy = dy / length
    let px = -uy, py = ux
    let headWidth = headLength * 0.62
    let backX = end.x - ux * headLength
    let backY = end.y - uy * headLength
    return ArrowGeometry(
        shaftEnd: CGPoint(x: backX, y: backY),
        tip: end,
        corner1: CGPoint(x: backX + px * headWidth / 2, y: backY + py * headWidth / 2),
        corner2: CGPoint(x: backX - px * headWidth / 2, y: backY - py * headWidth / 2)
    )
}
