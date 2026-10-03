import Cocoa

struct AnnotationRenderer {
    static let borderColor = RGBAColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 1)

    /// Border thickness for an image of `size`: scales with the capture so it reads the same on
    /// a small crop and a full Retina screen, never thinner than 2px.
    static func borderWidth(for size: CGSize) -> CGFloat {
        max(2, (max(size.width, size.height) / 600).rounded())
    }

    /// `image` with `style`'s finishing touches; unchanged when none are on. Border first, so the
    /// shadow is cast by the bordered card.
    static func applying(_ style: CopyStyle, to image: NSImage) -> NSImage {
        var result = image
        if style.border { result = addingBorder(to: result) }
        if style.shadow { result = addingShadow(to: result) }
        return result
    }

    /// `image` on transparent padding with a soft shadow beneath it. Sized relative to the image
    /// like the border, so it looks the same on a small crop and a full-screen capture.
    static func addingShadow(to image: NSImage) -> NSImage {
        let unit = max(1, (max(image.size.width, image.size.height) / 600).rounded())
        let blur = 12 * unit
        let offset = 4 * unit
        // Enough room on every side for the blur, plus the downward offset at the bottom.
        let pad = blur * 1.5
        let size = CGSize(width: image.size.width + pad * 2, height: image.size.height + pad * 2 + offset)
        let scale = image.pixelScale
        guard let context = NSImage.pixelContext(size: size, scale: scale), let source = image.bitmap else {
            return image
        }
        // Shadow offset and blur are in device pixels — the CTM doesn't scale them — so convert.
        // CG is y-up, so a negative y offset pushes the shadow down on screen.
        context.setShadow(
            offset: CGSize(width: 0, height: -offset * scale), blur: blur * scale,
            color: CGColor(gray: 0, alpha: 0.35)
        )
        context.draw(source, in: CGRect(x: pad, y: pad + offset, width: image.size.width, height: image.size.height))
        guard let cgImage = context.makeImage() else { return image }
        return NSImage(cgImage: cgImage, size: size)
    }

    /// `image` framed in a solid border, added around the outside so none of the capture is
    /// covered. Drawn at the image's own pixel density, for the same reason as `flatten`.
    static func addingBorder(to image: NSImage, width: CGFloat? = nil, color: RGBAColor = borderColor) -> NSImage {
        let inset = width ?? borderWidth(for: image.size)
        let size = CGSize(width: image.size.width + inset * 2, height: image.size.height + inset * 2)
        guard let context = NSImage.pixelContext(size: size, scale: image.pixelScale), let source = image.bitmap else {
            return image
        }
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.draw(source, in: CGRect(x: inset, y: inset, width: image.size.width, height: image.size.height))
        guard let cgImage = context.makeImage() else { return image }
        return NSImage(cgImage: cgImage, size: size)
    }

    /// The capture with every annotation drawn onto it, at the capture's full resolution.
    ///
    /// Rendered into an explicit CGContext at the base image's own pixel density (see
    /// `NSImage+PixelScale.swift`) rather than via `NSImage.lockFocus()`, which sizes its backing
    /// bitmap by whatever screen happens to be main — so the output would change resolution
    /// depending on which display the editor was on. Everything is drawn in points; the context's
    /// scale turns that into pixels.
    static func flatten(base: NSImage, annotations: [AnnotationObject]) -> NSImage {
        let size = base.size
        guard let context = NSImage.pixelContext(size: size, scale: base.pixelScale) else {
            return NSImage(size: size)
        }

        NSGraphicsContext.saveGraphicsState()
        // flipped: false matches CGContext's native bottom-left-origin, y-up convention,
        // which is also what NSImage.lockFocus() uses by default (verified empirically) —
        // so annotation frames drawn here line up with frames captured elsewhere against
        // an unflipped context.
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        if let bitmap = base.bitmap {
            context.draw(bitmap, in: CGRect(origin: .zero, size: size))
        } else {
            base.draw(in: CGRect(origin: .zero, size: size))
        }

        for annotation in annotations {
            draw(annotation, in: context, canvasSize: size)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = context.makeImage() else {
            return NSImage(size: size)
        }
        return NSImage(cgImage: cgImage, size: size)
    }

    private static func draw(_ annotation: AnnotationObject, in context: CGContext, canvasSize: CGSize) {
        context.saveGState()
        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(annotation.strokeWidth)

        switch annotation.kind {
        case .rectangle:
            context.stroke(annotation.frame)
        case .ellipse:
            context.strokeEllipse(in: annotation.frame)
        case .arrow(let start, let end):
            drawArrow(from: start, to: end, strokeWidth: annotation.strokeWidth, in: context)
        case .freehand(let points):
            drawFreehand(points, in: context)
        case .highlighter:
            context.setAlpha(0.35)
            context.fill(annotation.frame)
        case .blur:
            if annotation.redactionStyle == .solid {
                // Nothing sampled and nothing left behind — the strongest option.
                context.setFillColor(CGColor(gray: 0.12, alpha: 1))
                context.fill(annotation.frame)
            } else {
                drawRedaction(over: annotation.frame, in: context, canvasSize: canvasSize)
            }
        case .text(let string, let style):
            drawAnnotationText(string, style: style, in: annotation.frame, color: annotation.color, context: context)
        case .stamp(let kind):
            drawStamp(kind, in: annotation.frame, color: annotation.color, context: context)
        }

        context.restoreGState()
    }

    /// Replaces `frame` with a pixelated copy of whatever has been drawn under it.
    ///
    /// Sampled from a snapshot of the context rather than the base image, so a redaction placed
    /// over an earlier annotation covers that too — annotations are drawn in order, so everything
    /// beneath is already in the context.
    ///
    /// The snapshot is a `CGImage` (rows top-down) while `frame` is in the context's own
    /// bottom-left/y-up space, hence the flip to locate the region; drawing the result back at
    /// `frame` lands it upright again. Fully opaque by construction — the previous flat box was
    /// 90% opaque and let a tenth of the original pixels through into the export.
    private static func drawRedaction(over frame: CGRect, in context: CGContext, canvasSize: CGSize) {
        guard let snapshot = context.makeImage() else { return }
        // The snapshot is in pixels; `frame` and `canvasSize` are in points.
        let scale = canvasSize.width > 0 ? CGFloat(snapshot.width) / canvasSize.width : 1
        let topDown = CGRect(
            x: frame.origin.x,
            y: canvasSize.height - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        ).scaled(by: scale)
        guard let pixelated = Pixelation.pixelatedRegion(of: snapshot, in: topDown) else { return }
        context.draw(pixelated, in: frame)
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, strokeWidth: CGFloat, in context: CGContext) {
        let geo = arrowGeometry(from: start, to: end, strokeWidth: strokeWidth)

        context.move(to: start)
        context.addLine(to: geo.shaftEnd)
        context.strokePath()

        // A filled triangle, not two stroked line segments — two thick strokes meeting at a
        // point each still show their own flat (butt-cap) end near the tip, which reads as the
        // point being chopped off rather than coming to a clean apex. A filled shape has no such
        // cap artifact at any stroke width.
        context.move(to: geo.tip)
        context.addLine(to: geo.corner1)
        context.addLine(to: geo.corner2)
        context.closePath()
        context.fillPath()
    }

    private static func drawFreehand(_ points: [CGPoint], in context: CGContext) {
        guard let first = points.first else { return }
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private static func drawStamp(_ kind: StampKind, in frame: CGRect, color: RGBAColor, context: CGContext) {
        if let number = kind.number {
            drawNumberStamp(number, in: frame, color: color, context: context)
            return
        }
        if let glyph = kind.discGlyph {
            drawGlyphStamp(glyph, in: frame, color: color, context: context)
            return
        }
        let nsColor = NSColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        guard let symbolImage = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil) else { return }
        let tinted = symbolImage.tinted(with: nsColor)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        tinted.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Solid disc plus the digit in a contrasting colour — the flattened counterpart of
    /// `AnnotationOverlayShape.numberStamp`, kept in step with it via `StampKind.digitScale` so
    /// the exported image matches what the editor showed.
    /// Tick/cross: a solid disc with the bare glyph on top in a contrasting colour, matching how
    /// the numbered stamps are drawn. The `.circle.fill` symbols knock their mark out of the disc,
    /// so the capture showed through it.
    private static func drawGlyphStamp(_ glyph: String, in frame: CGRect, color: RGBAColor, context: CGContext) {
        let disc = discRect(in: frame)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: disc)

        let fg = color.contrastingForeground
        let config = NSImage.SymbolConfiguration(
            pointSize: disc.width * StampKind.glyphScale, weight: .bold
        )
        guard let symbol = NSImage(systemSymbolName: glyph, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let tinted = symbol.tinted(with: NSColor(red: fg.red, green: fg.green, blue: fg.blue, alpha: fg.alpha))

        let size = tinted.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        tinted.draw(in: CGRect(
            x: disc.midX - size.width / 2, y: disc.midY - size.height / 2,
            width: size.width, height: size.height
        ))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The largest circle centred in `frame` — `min` keeps stamps round in a non-square frame.
    private static func discRect(in frame: CGRect) -> CGRect {
        let side = min(frame.width, frame.height)
        return CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side)
    }

    private static func drawNumberStamp(_ number: Int, in frame: CGRect, color: RGBAColor, context: CGContext) {
        let disc = discRect(in: frame)
        let side = disc.width

        context.setFillColor(color.cgColor)
        context.fillEllipse(in: disc)

        let pointSize = side * StampKind.digitScale(for: number)
        let base = NSFont.systemFont(ofSize: pointSize, weight: .bold)
        // `.rounded` to match the SwiftUI side's `design: .rounded`; the descriptor falls back to
        // the plain system font on any OS that can't supply the rounded design.
        let font = NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: pointSize) ?? base
        let fg = color.contrastingForeground
        let attributed = NSAttributedString(string: "\(number)", attributes: [
            .foregroundColor: NSColor(red: fg.red, green: fg.green, blue: fg.blue, alpha: fg.alpha),
            .font: font
        ])

        // Centring the text's own line box (rather than its cap height) is what SwiftUI's `Text`
        // does inside the `ZStack` above, so both renderers land the digit in the same spot.
        let textSize = attributed.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributed.draw(at: CGPoint(x: disc.midX - textSize.width / 2, y: disc.midY - textSize.height / 2))
        NSGraphicsContext.restoreGraphicsState()
    }
}
