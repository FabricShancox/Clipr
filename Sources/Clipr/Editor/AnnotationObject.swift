import Foundation
import CoreGraphics

/// How a `.blur` annotation hides what's under it.
enum RedactionStyle: String, Codable {
    /// Averages the covered area into coarse blocks. Reads as "hidden" while still hinting at the
    /// shape of what was there.
    case pixelate
    /// A flat opaque block. The only option that leaves nothing at all to recover — pixelated text
    /// can sometimes be reconstructed by someone who knows the font and rendering.
    case solid
}

struct AnnotationObject: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: AnnotationKind
    var frame: CGRect
    var color: RGBAColor
    var strokeWidth: CGFloat
    /// Only meaningful for `.blur`. Deliberately an optional property rather than an associated
    /// value on `AnnotationKind`: giving the case a payload would change how every existing
    /// sidecar encodes, so previously-saved captures would fail to decode and get quarantined.
    /// Synthesized decoding treats a missing key for an Optional as `nil`, so old files keep
    /// working and `nil` means the original pixelate behaviour.
    var redactionStyle: RedactionStyle?

    /// Hit test with a generous tolerance so thin stroke-only shapes (arrow, freehand) — and
    /// small shapes in general — stay easy to click without having to land exactly on the
    /// outline pixel.
    func contains(_ point: CGPoint) -> Bool {
        let tolerance: CGFloat = max(strokeWidth, 10)
        return frame.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }
}

extension AnnotationObject {
    /// Shifts every point this annotation stores by `delta`, expressed in the same renderer
    /// space `frame` uses (bottom-left origin, y up). Used when the base image's own bounds
    /// change — crop or canvas resize — to carry existing annotations into the new coordinate
    /// system instead of discarding them.
    func translated(by delta: CGPoint) -> AnnotationObject {
        var copy = self
        copy.frame = frame.offsetBy(dx: delta.x, dy: delta.y)
        switch kind {
        case .freehand(let points):
            copy.kind = .freehand(points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) })
        case .arrow(let start, let end):
            copy.kind = .arrow(
                CGPoint(x: start.x + delta.x, y: start.y + delta.y),
                CGPoint(x: end.x + delta.x, y: end.y + delta.y)
            )
        default:
            break // frame move alone is enough for rectangle/ellipse/highlighter/blur/text/stamp
        }
        return copy
    }
}
