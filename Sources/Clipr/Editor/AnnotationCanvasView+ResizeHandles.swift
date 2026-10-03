import SwiftUI
import Cocoa

/// Per-shape resize handles: frame corners and edge midpoints, or the two endpoints for an arrow.
/// Shown on the selected annotation AND on whichever one the mouse is hovering, so a shape can be
/// grabbed and resized straight away without clicking it first. See `AnnotationCanvasView.swift`'s
/// header for how this file relates to the rest of the type.
extension AnnotationCanvasView {
    /// The annotations that currently show handles, already swapped for their live in-progress
    /// version while one is being resized. The one being resized is always included even if the
    /// mouse has drifted off it, since removing its handle mid-drag would cancel the gesture.
    var handleTargets: [AnnotationObject] {
        var ids: [UUID] = []
        for id in [hoveredID, soleSelectedID, resizingID].compactMap({ $0 }) where !ids.contains(id) {
            ids.append(id)
        }
        return ids.compactMap { id in
            guard id != editingTextID,
                  let stored = annotations.first(where: { $0.id == id }) else { return nil }
            if id == resizingID { return liveResized ?? stored }
            // Mid-move, the handles travel with the shape rather than staying behind.
            if movingIDs.contains(id) { return stored.translated(by: rendererDelta(of: moveOffset)) }
            return stored
        }
    }

    @ViewBuilder
    func resizeHandles(for annotation: AnnotationObject) -> some View {
        if case .arrow(let start, let end) = annotation.kind {
            resizeHandle(.arrowStart, id: annotation.id, at: swiftUIPoint(fromRendererPoint: start, canvasHeight: canvasHeight))
            resizeHandle(.arrowEnd, id: annotation.id, at: swiftUIPoint(fromRendererPoint: end, canvasHeight: canvasHeight))
        } else {
            let frame = swiftUIFrame(fromRendererFrame: annotation.frame, canvasHeight: canvasHeight)
            // Edge handles only once there's room for them between the corners on screen,
            // otherwise they pile up on top of the corner handles and steal their clicks.
            let roomForEdges = min(frame.width, frame.height) * canvasScale >= 40
            ForEach(roomForEdges ? ResizeHandle.corners + ResizeHandle.edges : ResizeHandle.corners, id: \.self) { handle in
                resizeHandle(handle, id: annotation.id, at: handle.position(on: frame))
            }
        }
    }

    func resizeHandle(_ handle: ResizeHandle, id: UUID, at point: CGPoint) -> some View {
        // A fixed size shrinks to a near-unhittable few screen pixels once the canvas is zoomed
        // out — dividing by `canvasScale` keeps the handle (and its stroke) a constant size on
        // screen at every zoom level. The hit target is deliberately larger than the dot drawn.
        let scale = max(canvasScale, 0.05)
        let dotSize = 10 / scale
        let hitSize = 22 / scale
        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5 / scale))
            .frame(width: dotSize, height: dotSize)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
            .position(point)
            .onHover { inside in
                if inside { handle.cursor.set() } else { (hoveredID != nil ? hoverCursor : NSCursor.arrow).set() }
            }
            // `.highPriorityGesture` so a drag starting exactly on a handle is claimed by the
            // handle's own gesture instead of bubbling up to the canvas-wide `DragGesture`
            // attached to the whole view in `body`.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let current = resizeAnchor(startingAt: point) + value.translation
                        handleResizeChanged(handle, id: id, current: current)
                    }
                    .onEnded { _ in
                        handleResizeEnded()
                        resizeHandleAnchor = nil
                    }
            )
    }

    /// A `DragGesture`'s `translation` is always cumulative from wherever THIS gesture began —
    /// but the handle's own `point` parameter is NOT fixed: once `handleResizeChanged` sets
    /// `resizingID`, `resizeHandles(for:)` starts computing the handle's position from the
    /// live-updating `liveResized` instead of the annotation's original geometry, so the handle
    /// being dragged visibly moves to follow the cursor on every single frame. Reading `point`
    /// fresh on each `onChanged` call (as an earlier version of this did) therefore added the
    /// FULL cumulative translation-since-gesture-start onto an already-updated position each
    /// time — a feedback loop that compounded every frame, which is what made resizing feel "far
    /// too sensitive" (a small mouse movement produced a runaway, much larger resize). Capturing
    /// the handle's position ONCE, the first time this gesture calls in, and reusing that same
    /// fixed anchor for the rest of the gesture eliminates the loop: `anchor + translation`
    /// always gives the correct absolute position no matter how many times the view re-renders
    /// mid-drag.
    private func resizeAnchor(startingAt point: CGPoint) -> CGPoint {
        if let resizeHandleAnchor { return resizeHandleAnchor }
        resizeHandleAnchor = point
        return point
    }

    /// Always computed from the STORED annotation (not the live one this view is drawing), for
    /// the same no-feedback-loop reason as `resizeAnchor`.
    func handleResizeChanged(_ handle: ResizeHandle, id: UUID, current: CGPoint) {
        guard let original = annotations.first(where: { $0.id == id }) else { return }
        resizingID = id
        // Grabbing a hovered-but-unselected shape's handle selects it, same as clicking it would.
        if selectedIDs != [id] { selectedIDs = [id] }
        switch handle {
        case .arrowStart, .arrowEnd:
            let point = rendererPoint(fromSwiftUIPoint: current, canvasHeight: canvasHeight)
            liveResized = original.movingArrowEndpoint(start: handle == .arrowStart, to: point)
        default:
            let frame = swiftUIFrame(fromRendererFrame: original.frame, canvasHeight: canvasHeight)
            let resized = handle.resizedFrame(frame, draggedTo: current)
            liveResized = original.resized(to: rendererFrame(fromSwiftUIFrame: resized, canvasHeight: canvasHeight))
        }
    }

    func handleResizeEnded() {
        defer {
            resizingID = nil
            liveResized = nil
        }
        guard let final = liveResized,
              let index = annotations.firstIndex(where: { $0.id == final.id }),
              isUsableSize(final) else { return }
        annotations[index] = final
    }

    /// Rejects a resize that collapsed the shape to nothing. Arrows and freehand strokes are lines,
    /// so only their overall extent matters — a horizontal arrow legitimately has zero height.
    private func isUsableSize(_ annotation: AnnotationObject) -> Bool {
        switch annotation.kind {
        case .arrow, .freehand:
            return max(annotation.frame.width, annotation.frame.height) > 4
        default:
            return annotation.frame.width > 4 && annotation.frame.height > 4
        }
    }
}

private extension ResizeHandle {
    var cursor: NSCursor {
        switch self {
        case .left, .right: return .resizeLeftRight
        case .top, .bottom: return .resizeUpDown
        default: return .crosshair
        }
    }
}

private func + (point: CGPoint, translation: CGSize) -> CGPoint {
    CGPoint(x: point.x + translation.width, y: point.y + translation.height)
}
