import CoreGraphics

enum AnnotationKind: Codable, Equatable {
    case rectangle
    case ellipse
    /// Explicit start/end points, not derived from `frame`: a `CGRect` is always normalized to
    /// a positive width/height, so reconstructing direction from `frame.minX/minY -> maxX/maxY`
    /// silently discards (or reverses) whichever diagonal the user actually dragged. Storing the
    /// real endpoints is what lets the arrowhead land on the end the user released, not always
    /// the geometrically-larger corner.
    case arrow(CGPoint, CGPoint)
    case freehand([CGPoint])
    case text(String, TextStyle)
    case highlighter
    case blur
    case stamp(StampKind)
}
