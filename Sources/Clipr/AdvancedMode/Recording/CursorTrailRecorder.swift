import CoreGraphics

/// The cursor's path since the last step, in global top-left coordinates. Mouse-moved events
/// arrive at display refresh rate; thinning to points at least `minDistance` apart and capping
/// the count keeps the resulting freehand annotation light without changing its visible shape.
struct CursorTrailRecorder {
    static let minDistance: CGFloat = 8
    static let maxPoints = 300

    private(set) var points: [CGPoint] = []

    mutating func add(_ point: CGPoint) {
        if let last = points.last, hypot(point.x - last.x, point.y - last.y) < Self.minDistance { return }
        points.append(point)
        if points.count > Self.maxPoints { points.removeFirst(points.count - Self.maxPoints) }
    }

    mutating func drain() -> [CGPoint] {
        defer { points = [] }
        return points
    }
}
