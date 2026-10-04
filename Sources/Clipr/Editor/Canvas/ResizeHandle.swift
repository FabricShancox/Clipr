import CoreGraphics

/// One grab point on an annotation's selection: a corner or edge midpoint of its frame, or — for
/// arrows, whose geometry is two explicit endpoints rather than a frame — one of those endpoints.
enum ResizeHandle: Hashable {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
    case arrowStart, arrowEnd

    static let corners: [ResizeHandle] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    static let edges: [ResizeHandle] = [.top, .bottom, .left, .right]

    /// Where this handle sits on `frame`. All in SwiftUI's y-down display space. Meaningless for
    /// the arrow endpoints, which are positioned from the arrow's points instead.
    func position(on frame: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: frame.minX, y: frame.minY)
        case .topRight: return CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeft: return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomRight: return CGPoint(x: frame.maxX, y: frame.maxY)
        case .top: return CGPoint(x: frame.midX, y: frame.minY)
        case .bottom: return CGPoint(x: frame.midX, y: frame.maxY)
        case .left: return CGPoint(x: frame.minX, y: frame.midY)
        case .right: return CGPoint(x: frame.maxX, y: frame.midY)
        case .arrowStart, .arrowEnd: return CGPoint(x: frame.midX, y: frame.midY)
        }
    }

    /// `frame` with this handle dragged to `point`, the opposite side held fixed. A corner moves
    /// both axes; an edge moves only its own, so dragging the top edge never changes the width.
    /// Dragging past the opposite side flips rather than producing a negative size.
    func resizedFrame(_ frame: CGRect, draggedTo point: CGPoint) -> CGRect {
        var minX = frame.minX, maxX = frame.maxX, minY = frame.minY, maxY = frame.maxY
        switch self {
        case .topLeft: minX = point.x; minY = point.y
        case .topRight: maxX = point.x; minY = point.y
        case .bottomLeft: minX = point.x; maxY = point.y
        case .bottomRight: maxX = point.x; maxY = point.y
        case .top: minY = point.y
        case .bottom: maxY = point.y
        case .left: minX = point.x
        case .right: maxX = point.x
        case .arrowStart, .arrowEnd: return frame
        }
        return CGRect(
            x: min(minX, maxX), y: min(minY, maxY),
            width: abs(maxX - minX), height: abs(maxY - minY)
        )
    }
}
