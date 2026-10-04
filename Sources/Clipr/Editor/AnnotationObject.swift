import Foundation
import CoreGraphics

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
    /// outline pixel. The canvas passes a zoom-adjusted `tolerance` so the target stays a
    /// usable size on screen when a large capture is zoomed out.
    ///
    /// Arrows and freehand strokes are lines, so for them the bounding box is only a cheap
    /// pre-filter: a long diagonal's box is mostly empty canvas, and treating all of it as "on"
    /// the arrow stole every click there from the drawing tools. They count as hit only within
    /// reach of the drawn path itself.
    func contains(_ point: CGPoint, tolerance: CGFloat = 10) -> Bool {
        guard hitRect(tolerance: tolerance).contains(point) else { return false }
        let reach = max(tolerance, strokeWidth / 2 + tolerance / 2)
        switch kind {
        case .arrow(let start, let end):
            // The head is wider than the shaft and sticks out past the tip, so the whole line
            // keeps the head's length as its reach — thin arrows stay easy to grab.
            let head = arrowHeadLength(for: strokeWidth)
            return distance(from: point, toSegment: start, end) <= max(reach, head)
        case .freehand(let points):
            guard let first = points.first else { return false }
            guard points.count > 1 else { return hypot(point.x - first.x, point.y - first.y) <= reach }
            return zip(points, points.dropFirst()).contains { distance(from: point, toSegment: $0, $1) <= reach }
        default:
            return true
        }
    }

    /// The invisible area that counts as "on" this annotation. Arrows get extra room: their frame
    /// is just the bounding box of the two endpoints, which for a near-horizontal or vertical
    /// arrow is a sliver with almost no height, and the head sticks out past it.
    func hitRect(tolerance: CGFloat = 10) -> CGRect {
        var pad = max(tolerance, strokeWidth)
        if case .arrow = kind {
            pad = max(pad, arrowHeadLength(for: strokeWidth))
        }
        return frame.insetBy(dx: -pad, dy: -pad)
    }

    /// Like `contains`, but a hollow box or ellipse only counts near its outline, not across its
    /// empty middle. Used while a drawing tool is active, so a second box can be drawn inside an
    /// existing one instead of every click there picking the outer one up.
    func outlineContains(_ point: CGPoint, tolerance: CGFloat = 10) -> Bool {
        guard contains(point, tolerance: tolerance) else { return false }
        let band = max(tolerance, strokeWidth)
        switch kind {
        case .rectangle:
            let inner = frame.insetBy(dx: band, dy: band)
            return inner.isNull || inner.isEmpty || !inner.contains(point)
        case .ellipse:
            let rx = frame.width / 2 - band, ry = frame.height / 2 - band
            guard rx > 0, ry > 0 else { return true }
            let dx = (point.x - frame.midX) / rx, dy = (point.y - frame.midY) / ry
            guard dx * dx + dy * dy >= 1 else { return false }
            // Also reject the corners of the frame, which are well outside the ellipse itself.
            let ox = (point.x - frame.midX) / (frame.width / 2 + band)
            let oy = (point.y - frame.midY) / (frame.height / 2 + band)
            return ox * ox + oy * oy <= 1
        default:
            return true
        }
    }

    /// Used to pick between overlapping hits: the smaller annotation wins, so an arrow or stamp
    /// sitting inside a large box or highlight can still be grabbed.
    var hitArea: CGFloat { frame.width * frame.height }
}

/// Shortest distance from `point` to the segment `a`–`b`.
func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
    let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
    return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
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

    /// This annotation stretched to fill `newFrame` (renderer space). Point-based kinds have
    /// their points mapped proportionally from the old frame into the new one, so resizing a
    /// freehand stroke actually rescales the stroke instead of only its bounding box.
    func resized(to newFrame: CGRect) -> AnnotationObject {
        var copy = self
        copy.frame = newFrame
        func map(_ p: CGPoint) -> CGPoint {
            // A straight horizontal/vertical stroke has a zero-size axis; keep it at the new
            // frame's edge rather than dividing by zero.
            let fx = frame.width > 0 ? (p.x - frame.minX) / frame.width : 0
            let fy = frame.height > 0 ? (p.y - frame.minY) / frame.height : 0
            return CGPoint(x: newFrame.minX + fx * newFrame.width, y: newFrame.minY + fy * newFrame.height)
        }
        switch kind {
        case .freehand(let points):
            copy.kind = .freehand(points.map(map))
        case .arrow(let start, let end):
            copy.kind = .arrow(map(start), map(end))
        default:
            break
        }
        return copy
    }

    /// An arrow with one endpoint moved to `point` (renderer space); its frame follows.
    func movingArrowEndpoint(start isStart: Bool, to point: CGPoint) -> AnnotationObject {
        guard case .arrow(let start, let end) = kind else { return self }
        var copy = self
        let newStart = isStart ? point : start
        let newEnd = isStart ? end : point
        copy.kind = .arrow(newStart, newEnd)
        copy.frame = CGRect(
            x: min(newStart.x, newEnd.x), y: min(newStart.y, newEnd.y),
            width: abs(newEnd.x - newStart.x), height: abs(newEnd.y - newStart.y)
        )
        return copy
    }
}
