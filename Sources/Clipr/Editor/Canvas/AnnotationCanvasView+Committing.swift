import CoreGraphics

/// Helpers for finishing an annotation (committing it, or preparing its display points) shared
/// across the gesture handlers in `AnnotationCanvasView+Gestures.swift`.
extension AnnotationCanvasView {
    /// Appends and selects the new annotation, so it can be deleted, recoloured, resized or
    /// restyled straight away without clicking it again first.
    func commit(_ annotation: AnnotationObject) {
        annotations.append(annotation)
        selectedIDs = [annotation.id]
        onAnnotationCommitted?(annotation)
    }

    func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Per-annotation-kind points needed by `AnnotationOverlayShape` for live rendering, already
    /// converted into SwiftUI display space:
    /// - `.freehand`: every stored (renderer-space) point, converted for the stroke path.
    /// - `.arrow`: the two explicit renderer-space endpoints, converted, so the displayed arrow
    ///   points the same direction the user actually dragged (see `AnnotationKind.arrow`'s doc).
    /// - everything else: unused by the shape, so empty.
    func displayPoints(for annotation: AnnotationObject) -> [CGPoint] {
        switch annotation.kind {
        case .freehand(let points):
            return points.map { swiftUIPoint(fromRendererPoint: $0, canvasHeight: canvasHeight) }
        case .arrow(let start, let end):
            return [
                swiftUIPoint(fromRendererPoint: start, canvasHeight: canvasHeight),
                swiftUIPoint(fromRendererPoint: end, canvasHeight: canvasHeight)
            ]
        default:
            return []
        }
    }
}
