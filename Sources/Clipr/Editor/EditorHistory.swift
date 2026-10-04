import Foundation

/// The editor's undo/redo stacks, lifted out so `EditorWindowController` can carry them across a
/// content-view rebuild, and so the stack rules can be tested without a view.
///
/// Undo lives in `EditorView`'s `@State`, which is discarded whenever the hosting view is
/// replaced. That is correct for most rebuilds — opening a different capture should not let you
/// undo into the previous one's history — but a rename changes nothing about the image or its
/// annotations, so losing the history there is pure loss.
///
/// Crop and canvas-resize deliberately keep clearing it. Restoring pre-crop annotations onto a
/// cropped image would place every one of them wrongly, since the operation remaps their
/// coordinates; undo would have to restore the old image too, which is a larger change than this.
struct EditorHistory: Equatable {
    var undo: [[AnnotationObject]] = []
    var redo: [[AnnotationObject]] = []
    /// The group the most recent entry belongs to — the id of the text annotation being typed
    /// into. Further changes in the same group fold into that entry instead of pushing their own,
    /// so typing a sentence is one undo step, not one per keystroke.
    var openGroup: UUID?

    /// Records that the annotations changed from `before` to `after`.
    ///
    /// - A change that leaves the array as it was records nothing. Pushing a no-op entry would
    ///   also clear redo, so a stray swatch click or a click on a resize handle silently threw
    ///   the redo stack away.
    /// - With a `group`, changes in the same group as the last one coalesce. If the group's net
    ///   effect is nothing at all — a text box placed and then abandoned empty — its entry is
    ///   dropped, so undo can't bring the empty box back.
    mutating func record(from before: [AnnotationObject], to after: [AnnotationObject], group: UUID? = nil) {
        guard before != after else { return }
        if let group, group == openGroup, !undo.isEmpty {
            if undo.last == after {
                undo.removeLast()
                openGroup = nil
            }
            return
        }
        undo.append(before)
        redo.removeAll()
        openGroup = group
    }

    /// Ends the current coalescing group, so the next change starts a new undo step.
    mutating func closeGroup() {
        openGroup = nil
    }

    /// Returns the state to restore, or `nil` when there's nothing to undo.
    mutating func popUndo(from current: [AnnotationObject]) -> [AnnotationObject]? {
        openGroup = nil
        guard let previous = undo.popLast() else { return nil }
        redo.append(current)
        return previous
    }

    mutating func popRedo(from current: [AnnotationObject]) -> [AnnotationObject]? {
        openGroup = nil
        guard let next = redo.popLast() else { return nil }
        undo.append(current)
        return next
    }
}

extension Set where Element == UUID {
    /// The members still present in `annotations` — undo and redo can remove whatever was
    /// selected, and a selection holding vanished ids kept color, stroke and nudge acting on
    /// nothing (each such "edit" used to wipe the redo stack).
    func pruned(to annotations: [AnnotationObject]) -> Set<UUID> {
        intersection(annotations.map(\.id))
    }
}

/// The number the numbered-stamp tool should offer next for these annotations: one past the
/// highest already placed, or 1 when there are none.
func nextStampNumber(after annotations: [AnnotationObject]) -> Int {
    let highest = annotations.compactMap { annotation -> Int? in
        if case .stamp(let kind) = annotation.kind { return kind.number }
        return nil
    }.max()
    return (highest ?? 0) + 1
}
