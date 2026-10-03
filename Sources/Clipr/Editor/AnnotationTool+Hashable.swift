/// `AnnotationTool` only declares `Equatable`, but SwiftUI's selection state in `EditorView`
/// requires `Hashable`. Synthesis of `hash(into:)` for an enum with an associated value only
/// happens automatically when the conformance is declared in the same file as the type, so it's
/// implemented by hand here; `StampKind` declares `Hashable` itself, so `hasher.combine(kind)`
/// below is valid.
extension AnnotationTool: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .select: hasher.combine(0)
        case .rectangle: hasher.combine(1)
        case .ellipse: hasher.combine(2)
        case .arrow: hasher.combine(3)
        case .freehand: hasher.combine(4)
        case .text: hasher.combine(5)
        case .highlighter: hasher.combine(6)
        case .blur: hasher.combine(7)
        case .crop: hasher.combine(9)
        case .stamp(let kind):
            hasher.combine(8)
            hasher.combine(kind)
        }
    }
}
