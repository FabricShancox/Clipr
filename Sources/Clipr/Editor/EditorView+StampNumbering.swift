/// The auto-incrementing numbered-stamp tool. See `EditorView.swift`'s header for how this file
/// relates to the rest of the type.
extension EditorView {
    func stampKind(for number: Int) -> StampKind {
        switch number {
        case 1: return .number1
        case 2: return .number2
        case 3: return .number3
        case 4: return .number4
        case 5: return .number5
        case 6: return .number6
        case 7: return .number7
        case 8: return .number8
        default: return .number9
        }
    }

    /// Called synchronously the instant a new annotation commits — see
    /// `AnnotationCanvasView.onAnnotationCommitted`. Auto-advancing here, right at the moment of
    /// placement, rather than inferring it later from an `annotations.count` change, is what
    /// makes the numbered-stamp counter reliably advance 1 -> 2 -> 3... on every placement.
    func handleAnnotationCommitted(_ annotation: AnnotationObject) {
        guard case .stamp(let kind) = annotation.kind, kind.number != nil else { return }
        nextStampNumber = min(nextStampNumber + 1, 9)
        selectedTool = .stamp(stampKind(for: nextStampNumber))
    }
}
