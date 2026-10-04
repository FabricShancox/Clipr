import Cocoa

/// Draws one `.text` annotation into `context` — split out of `AnnotationRenderer` since text
/// is the one annotation kind with its own non-trivial layout logic (alignment, border, measuring
/// for vertical placement) rather than a couple of CoreGraphics calls.
func drawAnnotationText(_ string: String, style: TextStyle, in frame: CGRect, color: RGBAColor, context: CGContext) {
    let nsColor = NSColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    let attributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: nsColor,
        .font: styledFont(style),
        .paragraphStyle: textParagraphStyle(for: style.horizontalAlign)
    ]
    let attributed = NSAttributedString(string: string, attributes: attributes)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    if style.border {
        nsColor.setStroke()
        NSBezierPath(roundedRect: textBorderRect(for: frame), xRadius: 4, yRadius: 4).stroke()
    }
    attributed.draw(in: verticallyAlignedTextRect(attributed, in: frame, align: style.verticalAlign))
    NSGraphicsContext.restoreGraphicsState()
}

func textParagraphStyle(for align: TextHorizontalAlign) -> NSParagraphStyle {
    let style = NSMutableParagraphStyle()
    switch align {
    case .left: style.alignment = .left
    case .center: style.alignment = .center
    case .right: style.alignment = .right
    }
    return style
}

/// `NSAttributedString.draw(in:)` always lays text out starting at the top of whatever rect it's
/// given (in this unflipped, y-up context that means the rect's `maxY` edge) — there's no
/// built-in "vertical alignment" option, so top/middle/bottom instead work by handing it a
/// shorter rect, positioned within `frame` at the right edge for each case, sized to the text's
/// own measured height.
func verticallyAlignedTextRect(_ attributed: NSAttributedString, in frame: CGRect, align: TextVerticalAlign) -> CGRect {
    let measured = attributed.boundingRect(
        with: CGSize(width: frame.width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin]
    )
    // Text taller than its frame (a sidecar from before boxes grew to fit) is drawn in full,
    // hanging down from the frame's top, rather than clipped to the frame — clipping silently
    // dropped words the user typed from every export.
    let height = ceil(measured.height)
    let yOffset: CGFloat
    if height > frame.height {
        yOffset = frame.height - height
    } else {
        switch align {
        case .top: yOffset = frame.height - height
        case .middle: yOffset = (frame.height - height) / 2
        case .bottom: yOffset = 0
        }
    }
    return CGRect(x: frame.origin.x, y: frame.origin.y + yOffset, width: frame.width, height: height)
}

/// Where the live text editor sits inside a text annotation's `frame` (SwiftUI space: top-left
/// origin, y down) so typing shows the text exactly where the static text and the renderer place
/// it for `align` — otherwise middle- and bottom-aligned text jumped when editing ended. Text
/// taller than the frame hangs from its top, as `verticallyAlignedTextRect` draws it.
func editingTextRect(in frame: CGRect, textHeight: CGFloat, align: TextVerticalAlign) -> CGRect {
    let y: CGFloat
    if textHeight >= frame.height {
        y = frame.minY
    } else {
        switch align {
        case .top: y = frame.minY
        case .middle: y = frame.minY + (frame.height - textHeight) / 2
        case .bottom: y = frame.maxY - textHeight
        }
    }
    return CGRect(x: frame.minX, y: y, width: frame.width, height: textHeight)
}

/// The border drawn around a bordered text annotation, the same in the editor (static and while
/// typing) and in every export: a few points outside the text frame so it doesn't touch the
/// glyphs.
func textBorderRect(for frame: CGRect) -> CGRect {
    frame.insetBy(dx: -textBorderInset.width, dy: -textBorderInset.height)
}

let textBorderInset = CGSize(width: 4, height: 2)

/// The height `string` needs when wrapped to `width` in `style`'s font — the one measurement the
/// editor's live box, its static display and the renderer all agree on.
func measuredTextHeight(_ string: String, style: TextStyle, width: CGFloat) -> CGFloat {
    // An empty string, or one ending in a newline, still occupies a line while the caret is on it.
    let measuring = string.isEmpty || string.hasSuffix("\n") ? string + " " : string
    let attributed = NSAttributedString(string: measuring, attributes: [
        .font: styledFont(style),
        .paragraphStyle: textParagraphStyle(for: style.horizontalAlign)
    ])
    let measured = attributed.boundingRect(
        with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin]
    )
    return ceil(measured.height)
}

extension AnnotationObject {
    /// A text annotation grown, if needed, to fit everything typed into it. The width stays what
    /// the user placed or dragged and the text wraps within it; the box grows downward on screen,
    /// keeping its top edge (renderer `maxY`) where it is. It never shrinks, so a deliberately tall
    /// box keeps its size. Other kinds are returned unchanged.
    func fittedToText() -> AnnotationObject {
        guard case .text(let string, let style) = kind else { return self }
        let needed = measuredTextHeight(string, style: style, width: frame.width)
        guard needed > frame.height else { return self }
        var copy = self
        copy.frame = CGRect(x: frame.minX, y: frame.maxY - needed, width: frame.width, height: needed)
        return copy
    }
}
