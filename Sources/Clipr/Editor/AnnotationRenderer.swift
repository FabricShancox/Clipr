import Cocoa

struct AnnotationRenderer {
    static func flatten(base: NSImage, annotations: [AnnotationObject]) -> NSImage {
        let size = base.size
        let pixelWidth = max(Int(size.width.rounded()), 1)
        let pixelHeight = max(Int(size.height.rounded()), 1)

        // Render into a pixel-exact CGContext rather than using NSImage.lockFocus(),
        // which sizes its backing bitmap by the screen's backing scale factor (e.g. 2x
        // on Retina displays). That would silently double the output's pixel dimensions
        // relative to `size`, which callers (and tests) rely on being 1:1 with points.
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(size: size)
        }

        NSGraphicsContext.saveGraphicsState()
        // flipped: false matches CGContext's native bottom-left-origin, y-up convention,
        // which is also what NSImage.lockFocus() uses by default (verified empirically) —
        // so annotation frames drawn here line up with frames captured elsewhere against
        // an unflipped context.
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        base.draw(in: CGRect(origin: .zero, size: size))

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
            drawRedaction(over: annotation.frame, in: context, canvasSize: canvasSize)
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
        let topDown = CGRect(
            x: frame.origin.x,
            y: canvasSize.height - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
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
    private static func drawNumberStamp(_ number: Int, in frame: CGRect, color: RGBAColor, context: CGContext) {
        let side = min(frame.width, frame.height)
        let disc = CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side)

        context.setFillColor(color.cgColor)
        context.fillEllipse(in: disc)

        let pointSize = side * StampKind.digitScale
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
