import SwiftUI

/// The main per-tool drag state machine — the canvas-wide `DragGesture` attached in
/// `AnnotationCanvasView.body`. See that file's header for how this file relates to the rest of
/// the type.
extension AnnotationCanvasView {
    func handleDragChanged(_ value: DragGesture.Value) {
        // Starting any new gesture — anywhere, with any tool — closes whatever text field was
        // open. Its content is already live-written via `editingTextBinding`, so this never
        // loses anything; it just returns the canvas to its normal (non-editing) state.
        if editingTextID != nil { editingTextID = nil }

        switch selectedTool {
        case .freehand:
            freehandPoints.append(value.location)
        case .select:
            if dragStart == nil {
                // One motion both selects AND (if it starts on a shape) moves it, rather than
                // requiring a separate "click to select, then a second drag to move" — hit-test
                // right at the start of the gesture, independent of whatever was selected
                // before.
                dragStart = value.startLocation
                let point = rendererPoint(fromSwiftUIPoint: value.startLocation, canvasHeight: canvasHeight)
                if let hit = annotations.last(where: { $0.contains(point) }) {
                    selectedID = hit.id
                    movingID = hit.id
                } else {
                    selectedID = nil
                    movingID = nil
                }
            }
            if movingID != nil {
                moveOffset = CGSize(width: value.location.x - value.startLocation.x, height: value.location.y - value.startLocation.y)
            }
        default:
            if dragStart == nil { dragStart = value.startLocation }
            dragCurrentLocation = value.location
        }
    }

    func handleDragEnded(_ value: DragGesture.Value) {
        switch selectedTool {
        case .select:
            // A pure click (no movement) only needed to select, which already happened in
            // `handleDragChanged` — committing a zero-delta "move" here would just spam the
            // undo stack with no-op entries.
            if let movingID, moveOffset != .zero, let index = annotations.firstIndex(where: { $0.id == movingID }) {
                // SwiftUI's drag delta is in y-down space; the stored geometry is in the
                // renderer's y-up space, so the y component of the delta flips sign too.
                let rendererDelta = CGPoint(x: moveOffset.width, y: -moveOffset.height)
                annotations[index] = annotations[index].translated(by: rendererDelta)
            }
            movingID = nil
            moveOffset = .zero
            dragStart = nil
        case .freehand:
            guard !freehandPoints.isEmpty else { return }
            let rendererPoints = freehandPoints.map { rendererPoint(fromSwiftUIPoint: $0, canvasHeight: canvasHeight) }
            commit(AnnotationObject(
                id: UUID(), kind: .freehand(rendererPoints),
                frame: boundingBox(of: rendererPoints),
                color: currentColor, strokeWidth: currentStrokeWidth
            ))
            freehandPoints = []
        case .text:
            let start = dragStart ?? value.location
            let dragged = rectBetween(start, value.location)
            // A real drag sizes the box; a plain click (or a drag too small to have been
            // deliberate) falls back to a sensible default sized to the current font, so
            // click-to-place still works.
            let minHeight = currentTextStyle.fontSize + 10
            let swiftUIFrame = dragged.width >= 24 && dragged.height >= 16
                ? CGRect(x: dragged.origin.x, y: dragged.origin.y, width: dragged.width, height: max(dragged.height, minHeight))
                : CGRect(x: start.x, y: start.y, width: 160, height: minHeight)
            let newAnnotation = AnnotationObject(
                id: UUID(), kind: .text("", currentTextStyle),
                frame: rendererFrame(fromSwiftUIFrame: swiftUIFrame, canvasHeight: canvasHeight),
                color: currentColor, strokeWidth: currentStrokeWidth
            )
            commit(newAnnotation)
            editingTextID = newAnnotation.id
            dragStart = nil
            dragCurrentLocation = nil
        case .stamp(let kind):
            let swiftUIFrame = CGRect(x: value.location.x - 16, y: value.location.y - 16, width: 32, height: 32)
            commit(AnnotationObject(
                id: UUID(), kind: .stamp(kind),
                frame: rendererFrame(fromSwiftUIFrame: swiftUIFrame, canvasHeight: canvasHeight),
                color: currentColor, strokeWidth: currentStrokeWidth
            ))
            // handleDragChanged's `default:` branch sets `dragStart` for any tool it doesn't
            // explicitly case (which includes .stamp, since a stamp is placed on drag-end, not
            // dragged out like a rect). Without this reset, a stale dragStart from placing a
            // stamp would corrupt the START POINT of the next rectangle/arrow/text/highlighter/
            // blur drag.
            dragStart = nil
            dragCurrentLocation = nil
        case .arrow:
            guard let start = dragStart else { return }
            let rendererStart = rendererPoint(fromSwiftUIPoint: start, canvasHeight: canvasHeight)
            let rendererEnd = rendererPoint(fromSwiftUIPoint: value.location, canvasHeight: canvasHeight)
            dragStart = nil
            dragCurrentLocation = nil
            guard hypot(value.location.x - start.x, value.location.y - start.y) > 2 else { return }
            commit(AnnotationObject(
                id: UUID(), kind: .arrow(rendererStart, rendererEnd),
                frame: boundingBox(of: [rendererStart, rendererEnd]),
                color: currentColor, strokeWidth: currentStrokeWidth
            ))
        case .crop:
            guard let start = dragStart else { return }
            let swiftUIFrame = rectBetween(start, value.location)
            dragStart = nil
            dragCurrentLocation = nil
            guard swiftUIFrame.width > 4, swiftUIFrame.height > 4 else { return }
            onCropRequested?(rendererFrame(fromSwiftUIFrame: swiftUIFrame, canvasHeight: canvasHeight))
        default:
            guard let start = dragStart else { return }
            let swiftUIFrame = rectBetween(start, value.location)
            dragStart = nil
            dragCurrentLocation = nil
            guard swiftUIFrame.width > 2, swiftUIFrame.height > 2 else { return }
            let kind: AnnotationKind
            switch selectedTool {
            case .ellipse: kind = .ellipse
            case .highlighter: kind = .highlighter
            case .blur: kind = .blur
            default: kind = .rectangle
            }
            commit(AnnotationObject(
                id: UUID(), kind: kind,
                frame: rendererFrame(fromSwiftUIFrame: swiftUIFrame, canvasHeight: canvasHeight),
                color: currentColor, strokeWidth: currentStrokeWidth
            ))
        }
    }

}
