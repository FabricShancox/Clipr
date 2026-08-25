import SwiftUI

/// Auto-save scheduling, undo/redo, and the annotations binding. See `EditorView.swift`'s header
/// for how this file relates to the rest of the type.
extension EditorView {
    /// Cancels any pending auto-save and schedules a new one ~800ms out. Called from
    /// `.onChange(of: annotations)`, so a burst of edits (typing, a multi-point freehand drag)
    /// collapses into a single write once things settle, instead of hitting disk on every
    /// intermediate state.
    func scheduleAutoSave() {
        autoSaveTask?.cancel()
        let snapshot = annotations
        let url = currentURL
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            onAutoSave(url, snapshot)
            withAnimation { showSavedConfirmation = true }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showSavedConfirmation = false }
        }
    }

    /// Every mutation to `annotations` — whether from the canvas (via `annotationsBinding`) or
    /// from this view directly (the toolbar's Delete button, the text-style controls acting on a
    /// selected text annotation) — funnels through here, so there's exactly one place that pushes
    /// an undo entry. A mutation made by directly assigning `annotations` elsewhere would
    /// silently skip the undo stack; routing everything through one function makes that
    /// impossible by construction.
    func mutateAnnotations(_ transform: (inout [AnnotationObject]) -> Void) {
        undoStack.append(annotations)
        redoStack.removeAll()
        var copy = annotations
        transform(&copy)
        annotations = copy
    }

    var annotationsBinding: Binding<[AnnotationObject]> {
        Binding(
            get: { annotations },
            set: { newValue in mutateAnnotations { $0 = newValue } }
        )
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    func deleteSelected() {
        guard let id = selectedAnnotationID else { return }
        mutateAnnotations { $0.removeAll { $0.id == id } }
        selectedAnnotationID = nil
    }
}
