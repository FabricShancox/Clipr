import SwiftUI

/// `TextStyle` -> SwiftUI `Font`, matching `styledFont(_:)`'s AppKit `NSFont` construction used
/// by `AnnotationRenderer` and the live text-editing overlay, so what you see while typing
/// matches what gets flattened into the saved image.
func styledSwiftUIFont(_ style: TextStyle) -> Font {
    var font = Font.system(size: style.fontSize)
    if style.bold { font = font.bold() }
    if style.italic { font = font.italic() }
    return font
}

/// `TextHorizontalAlign` -> SwiftUI's `TextAlignment`, for `.multilineTextAlignment`.
func swiftUITextAlignment(_ align: TextHorizontalAlign) -> TextAlignment {
    switch align {
    case .left: return .leading
    case .center: return .center
    case .right: return .trailing
    }
}

/// Combines both axes into the `Alignment` a `.frame(alignment:)` needs to position the static
/// (non-editing) `Text` view within its annotation's frame — `.multilineTextAlignment` alone only
/// controls how multiple LINES align relative to each other, not where the whole text block sits
/// within a frame taller/wider than the text itself.
func swiftUIFrameAlignment(horizontal: TextHorizontalAlign, vertical: TextVerticalAlign) -> Alignment {
    let h: HorizontalAlignment = horizontal == .left ? .leading : (horizontal == .right ? .trailing : .center)
    let v: VerticalAlignment = vertical == .top ? .top : (vertical == .bottom ? .bottom : .center)
    return Alignment(horizontal: h, vertical: v)
}
