import SwiftUI

/// The main per-tool drag state machine — the canvas-wide `DragGesture` attached in
/// `AnnotationCanvasView.body`. Per-kind annotation creation (text/stamp/arrow/crop/plain shape)
/// lives in `AnnotationCanvasView+ShapeCommit.swift`; this file is just the dispatch. See
/// `AnnotationCanvasView.swift`'s header for how these files relate to the rest of the type.
extension AnnotationCanvasView {
    func handleDragChanged(_ value: DragGesture.Value) {
        if editingTextID != nil {
            // Drops the annotation entirely if the user typed nothing — see `finishTextEditing`.
            finishTextEditing()
            // Snagit-style: clicking away from an actively-open text edit just finishes it —
            // its content is already live-written via `editingTextBinding`, so nothing is lost.
            // If the Text tool is still selected, this SAME click must not also place a brand
            // new text box on top; placing one takes a separate, later click. Any other tool
            // closing an open edit is free to proceed normally — switching tools and drawing
            // something new in one motion is a deliberate, different action.
            if selectedTool == .text, dragStart == nil {
                suppressTextPlacementForThisGesture = true
            }
        }
        guard !suppressTextPlacementForThisGesture else { return }

        if dragStart == nil {
            dragStart = value.startLocation
            // Clicking on an EXISTING annotation always selects (and, if dragged, moves) it,
            // regardless of which drawing tool is currently active — so something already
            // placed can be grabbed without switching to Select first, and a new element never
            // gets stacked on top of one the user was actually trying to select. Crop and
            // Freehand are excluded: Crop always acts on the whole canvas rather than a
            // specific element, and a freehand stroke starting on top of an existing shape is
            // normally "draw over it," not "pick it up."
            if selectedTool != .crop, selectedTool != .freehand {
                let point = rendererPoint(fromSwiftUIPoint: value.startLocation, canvasHeight: canvasHeight)
                if let hit = annotations.last(where: { $0.contains(point) }) {
                    selectedID = hit.id
                    movingID = hit.id
                } else {
                    selectedID = nil
                    movingID = nil
                }
            }
        }

        if movingID != nil {
            moveOffset = CGSize(width: value.location.x - value.startLocation.x, height: value.location.y - value.startLocation.y)
            return
        }

        switch selectedTool {
        case .freehand:
            freehandPoints.append(value.location)
        default:
            dragCurrentLocation = value.location
        }
    }

    func handleDragEnded(_ value: DragGesture.Value) {
        if suppressTextPlacementForThisGesture {
            suppressTextPlacementForThisGesture = false
            dragStart = nil
            return
        }

        // This gesture started on an existing annotation (see `handleDragChanged`): it selects
        // or moves that annotation instead of whatever the active tool would otherwise draw. A
        // pure click (no movement) only needed to select, which already happened in
        // `handleDragChanged` — committing a zero-delta "move" here would just spam the undo
        // stack with no-op entries.
        if let movingID {
            if moveOffset != .zero, let index = annotations.firstIndex(where: { $0.id == movingID }) {
                // SwiftUI's drag delta is in y-down space; the stored geometry is in the
                // renderer's y-up space, so the y component of the delta flips sign too.
                let rendererDelta = CGPoint(x: moveOffset.width, y: -moveOffset.height)
                annotations[index] = annotations[index].translated(by: rendererDelta)
            }
            self.movingID = nil
            moveOffset = .zero
            dragStart = nil
            return
        }

        switch selectedTool {
        case .select:
            dragStart = nil
        case .freehand:
            commitFreehand()
        case .text:
            commitText(endingAt: value.location)
        case .stamp(let kind):
            commitStamp(kind, at: value.location)
        case .arrow:
            commitArrow(endingAt: value.location)
        case .crop:
            commitCrop(endingAt: value.location)
        default:
            commitPlainShape(endingAt: value.location)
        }
    }
}
