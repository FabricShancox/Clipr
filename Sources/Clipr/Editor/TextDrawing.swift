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
        NSBezierPath(roundedRect: frame.insetBy(dx: -4, dy: -2), xRadius: 4, yRadius: 4).stroke()
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
    let height = min(measured.height, frame.height)
    let yOffset: CGFloat
    switch align {
    case .top: yOffset = frame.height - height
    case .middle: yOffset = (frame.height - height) / 2
    case .bottom: yOffset = 0
    }
    return CGRect(x: frame.origin.x, y: frame.origin.y + yOffset, width: frame.width, height: height)
}
