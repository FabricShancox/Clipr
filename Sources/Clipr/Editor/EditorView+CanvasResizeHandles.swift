import SwiftUI

/// The four corner canvas-resize handles. See `EditorView.swift`'s header for how this file
/// relates to the rest of the type.
extension EditorView {
    /// Small circular handles at the four corners of the capture, always visible, letting the
    /// user resize the canvas itself (not an individual annotation) by dragging a corner: inward
    /// crops away that area, outward adds transparent space. Positioned in the same untransformed
    /// image-point space `AnnotationCanvasView` renders at — this view sits in the same
    /// `.scaleEffect`-ed `ZStack` in `canvasArea`, so it scales identically alongside it. Sized by
    /// `1 / canvasScale` so the handle stays a constant, comfortably-clickable size on screen no
    /// matter how zoomed in or out the capture is.
    var canvasResizeHandles: some View {
        let w = image.size.width, h = image.size.height
        let handleSize = 14 / max(canvasScale, 0.05)
        return ZStack {
            canvasCornerHandle(.topLeft, at: CGPoint(x: 0, y: 0), fixed: CGPoint(x: w, y: h), size: handleSize)
            canvasCornerHandle(.topRight, at: CGPoint(x: w, y: 0), fixed: CGPoint(x: 0, y: h), size: handleSize)
            canvasCornerHandle(.bottomLeft, at: CGPoint(x: 0, y: h), fixed: CGPoint(x: w, y: 0), size: handleSize)
            canvasCornerHandle(.bottomRight, at: CGPoint(x: w, y: h), fixed: CGPoint(x: 0, y: 0), size: handleSize)
            if let pending = pendingCanvasResize {
                Rectangle()
                    .strokeBorder(EditorColors.accent, style: StrokeStyle(lineWidth: 2 / max(canvasScale, 0.05), dash: [5, 3]))
                    .frame(width: pending.width, height: pending.height)
                    .position(x: pending.midX, y: pending.midY)
                    .allowsHitTesting(false)
            }
        }
    }

    func canvasCornerHandle(_ corner: CanvasCorner, at point: CGPoint, fixed: CGPoint, size: CGFloat) -> some View {
        Circle()
            .fill(EditorColors.accent)
            .overlay(Circle().stroke(Color.white, lineWidth: 1.5 / max(canvasScale, 0.05)))
            .frame(width: size, height: size)
            .contentShape(Circle())
            .position(point)
            // Same reasoning as `AnnotationCanvasView.resizeHandle`: a `DragGesture` on this
            // small circle reports `location` in the circle's own tiny local frame, not image
            // space, so the image-space position is reconstructed from this handle's known
            // `point` plus the gesture's (space-independent) `translation`.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let current = CGPoint(x: point.x + value.translation.width, y: point.y + value.translation.height)
                        pendingCanvasResize = rectBetween(fixed, current)
                    }
                    .onEnded { value in
                        let current = CGPoint(x: point.x + value.translation.width, y: point.y + value.translation.height)
                        let rect = rectBetween(fixed, current)
                        pendingCanvasResize = nil
                        guard rect.width > 4, rect.height > 4 else { return }
                        onCanvasResize(rect, annotations)
                    }
            )
            .help("Drag to resize the canvas — inward crops, outward adds transparent space")
    }

    func rectBetween(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
