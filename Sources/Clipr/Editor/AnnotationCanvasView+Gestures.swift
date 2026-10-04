import SwiftUI
import Cocoa

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
            beginGesture(at: value.startLocation)
        }

        if !movingIDs.isEmpty {
            moveOffset = CGSize(width: value.location.x - value.startLocation.x, height: value.location.y - value.startLocation.y)
            return
        }

        switch selectedTool {
        case .freehand:
            freehandPoints.append(value.location)
        case .select:
            dragCurrentLocation = value.location
            isMarqueeSelecting = true
        default:
            dragCurrentLocation = constrained(value.location, from: value.startLocation)
        }
    }

    /// Decides, once per gesture, what the press grabbed.
    ///
    /// Clicking on an EXISTING annotation always selects (and, if dragged, moves) it, regardless
    /// of which drawing tool is currently active — so something already placed can be grabbed
    /// without switching to Select first, and a new element never gets stacked on top of one the
    /// user was actually trying to select. Crop and Freehand are excluded: Crop always acts on
    /// the whole canvas rather than a specific element, and a freehand stroke starting on top of
    /// an existing shape is normally "draw over it," not "pick it up."
    ///
    /// Shift-click adds or removes an annotation from the selection. Pressing on something that
    /// is already part of a multi-selection keeps the whole group selected so it moves together.
    private func beginGesture(at location: CGPoint) {
        guard selectedTool != .crop, selectedTool != .freehand else {
            if !NSEvent.modifierFlags.contains(.shift) { selectedIDs = [] }
            return
        }
        let extending = NSEvent.modifierFlags.contains(.shift)
        guard let hit = annotation(atSwiftUIPoint: location) else {
            if !extending { selectedIDs = [] }
            movingIDs = []
            return
        }
        if extending {
            if selectedIDs.contains(hit.id) { selectedIDs.remove(hit.id) } else { selectedIDs.insert(hit.id) }
            movingIDs = selectedIDs
        } else if selectedIDs.contains(hit.id) {
            movingIDs = selectedIDs
        } else {
            selectedIDs = [hit.id]
            movingIDs = [hit.id]
        }
        // Shift-clicking the last selected one off leaves nothing to drag; fall back to a no-op
        // gesture rather than drawing with the active tool.
        if movingIDs.isEmpty { movingIDs = [hit.id] }
    }

    func handleDragEnded(_ value: DragGesture.Value) {
        if suppressTextPlacementForThisGesture {
            suppressTextPlacementForThisGesture = false
            dragStart = nil
            return
        }

        // This gesture started on an existing annotation (see `beginGesture`): it selects or
        // moves the selection instead of whatever the active tool would otherwise draw. A pure
        // click (no movement) only needed to select, which already happened — committing a
        // zero-delta "move" here would just spam the undo stack with no-op entries.
        if !movingIDs.isEmpty {
            if moveOffset != .zero {
                let delta = rendererDelta(of: moveOffset)
                annotations = annotations.map { movingIDs.contains($0.id) ? $0.translated(by: delta) : $0 }
            } else if (NSApp.currentEvent?.clickCount ?? 1) >= 2, movingIDs.count == 1,
                      let id = movingIDs.first,
                      let hit = annotations.first(where: { $0.id == id }), case .text = hit.kind {
                // Double-clicking placed text opens it for editing again, so a typo can be fixed
                // without deleting and retyping it.
                selectedIDs = [id]
                editingTextID = id
            }
            movingIDs = []
            moveOffset = .zero
            dragStart = nil
            return
        }

        switch selectedTool {
        case .select:
            finishMarquee(endingAt: value.location)
        case .freehand:
            commitFreehand()
        case .text:
            commitText(endingAt: value.location)
        case .stamp(let kind):
            commitStamp(kind, at: value.location)
        case .arrow:
            commitArrow(endingAt: constrained(value.location, from: value.startLocation))
        case .crop:
            commitCrop(endingAt: value.location)
        default:
            commitPlainShape(endingAt: constrained(value.location, from: value.startLocation))
        }
    }

    /// Selects everything the Select-tool marquee touches. Shift adds to the existing selection.
    private func finishMarquee(endingAt location: CGPoint) {
        defer {
            dragStart = nil
            dragCurrentLocation = nil
            isMarqueeSelecting = false
        }
        guard isMarqueeSelecting, let start = dragStart else { return }
        let swiftUIRect = rectBetween(start, location)
        guard swiftUIRect.width > 2 || swiftUIRect.height > 2 else { return }
        let rect = rendererFrame(fromSwiftUIFrame: swiftUIRect, canvasHeight: canvasHeight)
        // `hitRect(tolerance: 1)` rather than `frame` so a perfectly horizontal arrow (zero-height
        // frame) can still be caught.
        let touched = annotations.filter { $0.hitRect(tolerance: 1).intersects(rect) }.map(\.id)
        if NSEvent.modifierFlags.contains(.shift) {
            selectedIDs.formUnion(touched)
        } else {
            selectedIDs = Set(touched)
        }
    }

    /// SwiftUI's drag delta is in y-down space; the stored geometry is in the renderer's y-up
    /// space, so the y component of the delta flips sign.
    func rendererDelta(of offset: CGSize) -> CGPoint {
        CGPoint(x: offset.width, y: -offset.height)
    }
}
