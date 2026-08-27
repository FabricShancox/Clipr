import SwiftUI

/// Per-shape corner resize handles, shown on the currently-selected annotation. See
/// `AnnotationCanvasView.swift`'s header for how this file relates to the rest of the type.
extension AnnotationCanvasView {
    /// Resize handles only make sense for annotations whose geometry is a plain rectangular
    /// frame — `.freehand`/`.arrow` store their own explicit point lists, so resizing "the
    /// frame" wouldn't resize the actual stroke.
    func resizeHandlesApply(to annotation: AnnotationObject) -> Bool {
        switch annotation.kind {
        case .freehand, .arrow: return false
        default: return true
        }
    }

    @ViewBuilder
    func resizeHandles(for annotation: AnnotationObject) -> some View {
        let frame = annotation.id == resizingID
            ? (liveResizeFrame ?? swiftUIFrame(fromRendererFrame: annotation.frame, canvasHeight: canvasHeight))
            : swiftUIFrame(fromRendererFrame: annotation.frame, canvasHeight: canvasHeight)
        Group {
            resizeHandle(.topLeft, annotation: annotation, at: CGPoint(x: frame.minX, y: frame.minY))
            resizeHandle(.topRight, annotation: annotation, at: CGPoint(x: frame.maxX, y: frame.minY))
            resizeHandle(.bottomLeft, annotation: annotation, at: CGPoint(x: frame.minX, y: frame.maxY))
            resizeHandle(.bottomRight, annotation: annotation, at: CGPoint(x: frame.maxX, y: frame.maxY))
        }
    }

    func resizeHandle(_ corner: ResizeCorner, annotation: AnnotationObject, at point: CGPoint) -> some View {
        // A fixed 10-point handle shrinks to a near-unhittable few screen pixels once the
        // canvas is zoomed out — dividing by `canvasScale` keeps the handle (and its stroke) a
        // constant size on screen at every zoom level.
        let size = 10 / max(canvasScale, 0.05)
        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5 / max(canvasScale, 0.05)))
            .frame(width: size, height: size)
            .contentShape(Circle())
            .position(point)
            // `.highPriorityGesture` so a drag starting exactly on a handle is claimed by the
            // handle's own gesture instead of bubbling up to the canvas-wide `DragGesture`
            // attached to the whole view in `body`.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let current = resizeAnchor(startingAt: point) + value.translation
                        handleResizeChanged(corner, annotation: annotation, current: current)
                    }
                    .onEnded { value in
                        let current = resizeAnchor(startingAt: point) + value.translation
                        handleResizeEnded(corner, annotation: annotation, current: current)
                        resizeHandleAnchor = nil
                    }
            )
    }

    /// A `DragGesture`'s `translation` is always cumulative from wherever THIS gesture began —
    /// but the handle's own `point` parameter is NOT fixed: once `handleResizeChanged` sets
    /// `resizingID`, `resizeHandles(for:)` starts computing the handle's position from the
    /// live-updating `liveResizeFrame` instead of the annotation's original frame, so the handle
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

    func handleResizeChanged(_ corner: ResizeCorner, annotation: AnnotationObject, current: CGPoint) {
        resizingID = annotation.id
        resizeCorner = corner
        let originalFrame = swiftUIFrame(fromRendererFrame: annotation.frame, canvasHeight: canvasHeight)
        let fixed: CGPoint
        switch corner {
        case .topLeft: fixed = CGPoint(x: originalFrame.maxX, y: originalFrame.maxY)
        case .topRight: fixed = CGPoint(x: originalFrame.minX, y: originalFrame.maxY)
        case .bottomLeft: fixed = CGPoint(x: originalFrame.maxX, y: originalFrame.minY)
        case .bottomRight: fixed = CGPoint(x: originalFrame.minX, y: originalFrame.minY)
        }
        liveResizeFrame = rectBetween(fixed, current)
    }

    func handleResizeEnded(_ corner: ResizeCorner, annotation: AnnotationObject, current: CGPoint) {
        defer {
            resizingID = nil
            resizeCorner = nil
            liveResizeFrame = nil
        }
        guard let finalFrame = liveResizeFrame,
              let index = annotations.firstIndex(where: { $0.id == annotation.id }),
              finalFrame.width > 4, finalFrame.height > 4 else { return }
        annotations[index].frame = rendererFrame(fromSwiftUIFrame: finalFrame, canvasHeight: canvasHeight)
    }
}

private func + (point: CGPoint, translation: CGSize) -> CGPoint {
    CGPoint(x: point.x + translation.width, y: point.y + translation.height)
}
