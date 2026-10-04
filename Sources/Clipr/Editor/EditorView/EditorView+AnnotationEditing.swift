import SwiftUI

/// Operations on the selection — duplicate, nudge, reorder, select all, and copy/cut/paste of
/// annotations. See `EditorView.swift`'s header for how this file relates to the rest of the type.
///
/// Everything here goes through `mutateAnnotations`, so each operation is a single undo step
/// without needing its own bookkeeping.
extension EditorView {
    func duplicateSelected() {
        let originals = annotations.filter { selectedIDs.contains($0.id) }
        guard !originals.isEmpty else { return }
        let copies = originals.map { $0.translated(by: AnnotationClipboard.pasteOffset).withNewID() }
        mutateAnnotations { $0.append(contentsOf: copies) }
        // Select the copies, so a duplicate can immediately be dragged into place — and so
        // repeating ⌘D walks a trail rather than stacking every copy on the same spot.
        selectedIDs = Set(copies.map(\.id))
    }

    /// Moves the selection by whole points. `frame` is in renderer space (bottom-left origin, y
    /// up), so an on-screen "up" is a positive y — callers pass screen-sense values and this
    /// flips them, keeping the call sites readable.
    func nudgeSelected(dx: CGFloat, dy: CGFloat) {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        mutateAnnotations { annotations in
            for index in annotations.indices where ids.contains(annotations[index].id) {
                annotations[index] = annotations[index].translated(by: CGPoint(x: dx, y: -dy))
            }
        }
    }

    func selectAll() {
        selectedIDs = Set(annotations.map(\.id))
    }

    /// Annotations render in array order, so z-order is position: later entries draw on top.
    /// Forward/backward step one place and only make sense for a single annotation; front/back
    /// move the whole selection, keeping its members' order among themselves.
    func bringSelectedForward() {
        moveSole { index, count in min(index + 1, count - 1) }
    }

    func sendSelectedBackward() {
        moveSole { index, _ in max(index - 1, 0) }
    }

    func bringSelectedToFront() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        mutateAnnotations { list in
            list = list.filter { !ids.contains($0.id) } + list.filter { ids.contains($0.id) }
        }
    }

    func sendSelectedToBack() {
        let ids = selectedIDs
        guard !ids.isEmpty else { return }
        mutateAnnotations { list in
            list = list.filter { ids.contains($0.id) } + list.filter { !ids.contains($0.id) }
        }
    }

    private func moveSole(_ destination: (_ index: Int, _ count: Int) -> Int) {
        guard selectedIDs.count == 1, let id = selectedIDs.first else { return }
        mutateAnnotations { annotations in
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
            let target = destination(index, annotations.count)
            guard target != index else { return }
            let moved = annotations.remove(at: index)
            annotations.insert(moved, at: target)
        }
    }

    // MARK: - Clipboard

    /// ⌘C: the selected annotations, so they can be pasted elsewhere. With nothing selected it
    /// copies the annotated image instead, the same as the Copy button.
    func copySelection() {
        let selected = annotations.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else {
            onCopy(annotations)
            return
        }
        AnnotationClipboard(canvasHeight: image.size.height, annotations: selected).write()
    }

    func cutSelection() {
        guard !selectedIDs.isEmpty else { return }
        copySelection()
        deleteSelected()
    }

    /// ⌘V: annotations copied from this or any other capture, selected once placed.
    func pasteAnnotations() {
        guard let clipboard = AnnotationClipboard.read() else { return }
        let pasted = clipboard.annotationsForPaste(into: image.size, existing: annotations)
        guard !pasted.isEmpty else { return }
        mutateAnnotations { $0.append(contentsOf: pasted) }
        selectedIDs = Set(pasted.map(\.id))
    }

    /// Zero-size buttons carrying the shortcuts, same approach as `toolShortcuts` — SwiftUI has no
    /// lighter way to bind a bare key outside a visible control. All are disabled while a text
    /// field is active so arrow keys move the caret, and while nothing is selected.
    var annotationEditingShortcuts: some View {
        let unavailable = selectedIDs.isEmpty || isTextEntryActive
        return Group {
            Group {
                Button("") { duplicateSelected() }
                    .keyboardShortcut("d", modifiers: .command)
                Button("") { nudgeSelected(dx: 0, dy: -1) }.keyboardShortcut(.upArrow, modifiers: [])
                Button("") { nudgeSelected(dx: 0, dy: 1) }.keyboardShortcut(.downArrow, modifiers: [])
                Button("") { nudgeSelected(dx: -1, dy: 0) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { nudgeSelected(dx: 1, dy: 0) }.keyboardShortcut(.rightArrow, modifiers: [])
                // Shift for a coarse nudge, the usual convention.
                Button("") { nudgeSelected(dx: 0, dy: -10) }.keyboardShortcut(.upArrow, modifiers: .shift)
                Button("") { nudgeSelected(dx: 0, dy: 10) }.keyboardShortcut(.downArrow, modifiers: .shift)
                Button("") { nudgeSelected(dx: -10, dy: 0) }.keyboardShortcut(.leftArrow, modifiers: .shift)
                Button("") { nudgeSelected(dx: 10, dy: 0) }.keyboardShortcut(.rightArrow, modifiers: .shift)
            }
            .disabled(unavailable)
            Group {
                Button("") { bringSelectedForward() }.keyboardShortcut("]", modifiers: .command)
                Button("") { sendSelectedBackward() }.keyboardShortcut("[", modifiers: .command)
                Button("") { bringSelectedToFront() }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("") { sendSelectedToBack() }.keyboardShortcut("[", modifiers: [.command, .shift])
            }
            .disabled(unavailable)
            // Bare [ and ] step the stroke preset, for the selection or the next shape — so these
            // only need a text field to be inactive, not a selection.
            Group {
                Button("") { stepStrokeWidth(by: -1) }.keyboardShortcut("[", modifiers: [])
                Button("") { stepStrokeWidth(by: 1) }.keyboardShortcut("]", modifiers: [])
            }
            .disabled(isTextEntryActive)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
