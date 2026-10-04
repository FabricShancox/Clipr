import SwiftUI

/// The auto-incrementing numbered-stamp tool. See `EditorView.swift`'s header for how this file
/// relates to the rest of the type.
extension EditorView {
    static let maxStampNumber = 999

    func stampKind(for number: Int) -> StampKind {
        .numbered(min(max(number, 1), Self.maxStampNumber))
    }

    /// Called synchronously the instant a new annotation commits — see
    /// `AnnotationCanvasView.onAnnotationCommitted`. Auto-advancing here, right at the moment of
    /// placement, rather than inferring it later from an `annotations.count` change, is what
    /// makes the numbered-stamp counter reliably advance 1 -> 2 -> 3... on every placement.
    func handleAnnotationCommitted(_ annotation: AnnotationObject) {
        guard case .stamp(let kind) = annotation.kind, let number = kind.number else { return }
        setNextStampNumber(number + 1)
    }

    /// Sets which number the next numbered stamp places — from the stamp popover, or after each
    /// placement — and keeps the active tool in step if it's the numbered stamp.
    func setNextStampNumber(_ number: Int) {
        let wasNumbering = selectedTool == numberTool
        nextStampNumber = min(max(number, 1), Self.maxStampNumber)
        if wasNumbering { selectedTool = numberTool }
    }

    /// Reopening a capture continues after the highest step already on it, rather than starting
    /// again at 1 and placing a second "1".
    func resumeStampNumbering() {
        let highest = annotations.compactMap { annotation -> Int? in
            if case .stamp(let kind) = annotation.kind { return kind.number }
            return nil
        }.max()
        if let highest { setNextStampNumber(highest + 1) }
    }
}
