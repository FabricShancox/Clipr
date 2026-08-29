import SwiftUI

/// Operations on the selected annotation — duplicate, nudge, reorder. See `EditorView.swift`'s
/// header for how this file relates to the rest of the type.
///
/// Everything here goes through `mutateAnnotations`, so each operation is a single undo step
/// without needing its own bookkeeping.
extension EditorView {
    /// Offset applied to a duplicate so it doesn't land exactly on the original and look like
    /// nothing happened. In renderer space (y up), so down-right on screen is -y.
    private static let duplicateOffset = CGPoint(x: 12, y: -12)

    func duplicateSelected() {
        guard let id = selectedAnnotationID,
              let original = annotations.first(where: { $0.id == id }) else { return }

        // Rebuilt rather than mutated: `id` is a `let`, and a duplicate must not share the
        // original's identity or selection and `ForEach` would confuse the two.
        let moved = original.translated(by: Self.duplicateOffset)
        let copy = AnnotationObject(
            id: UUID(), kind: moved.kind, frame: moved.frame,
            color: moved.color, strokeWidth: moved.strokeWidth
        )
        mutateAnnotations { $0.append(copy) }
        // Select the copy, so a duplicate can immediately be dragged into place — and so
        // repeating ⌘D walks a trail rather than stacking every copy on the same spot.
        selectedAnnotationID = copy.id
    }

    /// Moves the selection by whole points. `frame` is in renderer space (bottom-left origin, y
    /// up), so an on-screen "up" is a positive y — callers pass screen-sense values and this
    /// flips them, keeping the call sites readable.
    func nudgeSelected(dx: CGFloat, dy: CGFloat) {
        guard let id = selectedAnnotationID else { return }
        mutateAnnotations { annotations in
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
            annotations[index] = annotations[index].translated(by: CGPoint(x: dx, y: -dy))
        }
    }

    /// Annotations render in array order, so z-order is position: later entries draw on top.
    func bringSelectedForward() {
        moveSelected { index, count in min(index + 1, count - 1) }
    }

    func sendSelectedBackward() {
        moveSelected { index, _ in max(index - 1, 0) }
    }

    func bringSelectedToFront() {
        moveSelected { _, count in count - 1 }
    }

    func sendSelectedToBack() {
        moveSelected { _, _ in 0 }
    }

    private func moveSelected(_ destination: (_ index: Int, _ count: Int) -> Int) {
        guard let id = selectedAnnotationID else { return }
        mutateAnnotations { annotations in
            guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
            let target = destination(index, annotations.count)
            guard target != index else { return }
            let moved = annotations.remove(at: index)
            annotations.insert(moved, at: target)
        }
    }

    /// Zero-size buttons carrying the shortcuts, same approach as `toolShortcuts` — SwiftUI has no
    /// lighter way to bind a bare key outside a visible control. All are disabled while a text
    /// field is active so arrow keys move the caret, and while nothing is selected.
    var annotationEditingShortcuts: some View {
        let unavailable = selectedAnnotationID == nil || isTextEntryActive
        return Group {
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
            Group {
                Button("") { bringSelectedForward() }.keyboardShortcut("]", modifiers: .command)
                Button("") { sendSelectedBackward() }.keyboardShortcut("[", modifiers: .command)
                Button("") { bringSelectedToFront() }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("") { sendSelectedToBack() }.keyboardShortcut("[", modifiers: [.command, .shift])
            }
        }
        .disabled(unavailable)
        .opacity(0)
        .frame(width: 0, height: 0)
    }
}
