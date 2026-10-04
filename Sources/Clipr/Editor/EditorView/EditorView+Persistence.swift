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
    ///
    /// While a text annotation is being typed into, its changes share one undo group (see
    /// `EditorHistory.record`), so the whole edit — placing the box and typing into it — undoes
    /// in one step, and abandoning an empty box leaves nothing behind to undo back into.
    func mutateAnnotations(_ transform: (inout [AnnotationObject]) -> Void) {
        let before = annotations
        var copy = annotations
        transform(&copy)
        guard copy != before else { return }
        history.record(from: before, to: copy, group: editingTextID)
        annotations = copy
    }

    var annotationsBinding: Binding<[AnnotationObject]> {
        Binding(
            get: { annotations },
            set: { newValue in mutateAnnotations { $0 = newValue } }
        )
    }

    func undo() {
        let before = annotations
        guard let previous = history.popUndo(from: annotations) else { return }
        annotations = previous
        afterHistoryJump(from: before)
    }

    func redo() {
        let before = annotations
        guard let next = history.popRedo(from: annotations) else { return }
        annotations = next
        afterHistoryJump(from: before)
    }

    /// Undo and redo can remove whatever was selected or being edited. A selection left holding
    /// vanished ids kept the color, stroke and nudge controls live, and each of those "edits" of
    /// nothing used to wipe the redo stack. The numbered stamp also follows what's actually on
    /// the canvas, so undoing stamp 3 offers 3 again rather than skipping to 4 — but only when the
    /// jump actually changed the stamps, so a "Next" number picked by hand survives undoing a box.
    private func afterHistoryJump(from before: [AnnotationObject]) {
        selectedIDs = selectedIDs.pruned(to: annotations)
        if let id = editingTextID, !annotations.contains(where: { $0.id == id }) {
            editingTextID = nil
        }
        if Clipr.nextStampNumber(after: before) != Clipr.nextStampNumber(after: annotations) {
            setNextStampNumber(Clipr.nextStampNumber(after: annotations))
        }
    }

    func deleteSelected() {
        guard !selectedIDs.isEmpty else { return }
        let ids = selectedIDs
        mutateAnnotations { $0.removeAll { ids.contains($0.id) } }
        selectedIDs = []
    }
}
