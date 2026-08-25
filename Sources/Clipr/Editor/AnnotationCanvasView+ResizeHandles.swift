import SwiftUI

/// Per-shape corner resize handles, shown on the currently-selected annotation (see
/// `AnnotationCanvasView.resizeHandlesApply`). See `AnnotationCanvasView.swift`'s header for how
/// this file relates to the rest of the type.
extension AnnotationCanvasView {
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
        // canvas is zoomed out, which read as "far too sensitive" — any small mouse movement
        // while hunting for that tiny target produced a large relative change. Dividing by
        // `canvasScale` keeps the handle (and its stroke) a constant size on screen at every
        // zoom level.
        let size = 10 / max(canvasScale, 0.05)
        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5 / max(canvasScale, 0.05)))
            .frame(width: size, height: size)
            .contentShape(Circle())
            .position(point)
            // `.highPriorityGesture` so a drag starting exactly on a handle is claimed by the
            // handle's own gesture instead of bubbling up to the canvas-wide `DragGesture`
            // attached to the whole view in `body` (which would otherwise try to interpret the
            // same drag as drawing a brand new annotation).
            //
            // A `DragGesture` reports `location`/`startLocation` in the *attached view's own*
            // local coordinate space — for this handle, that's roughly a 0...`size` range, not
            // canvas space. `translation` is the one value that's space-independent (just an
            // accumulated points-moved delta), so the canvas-space position is reconstructed as
            // this handle's own known `point` (already in canvas space) plus that delta.
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let current = CGPoint(x: point.x + value.translation.width, y: point.y + value.translation.height)
                        handleResizeChanged(corner, annotation: annotation, current: current)
                    }
                    .onEnded { value in
                        let current = CGPoint(x: point.x + value.translation.width, y: point.y + value.translation.height)
                        handleResizeEnded(corner, annotation: annotation, current: current)
                    }
            )
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
