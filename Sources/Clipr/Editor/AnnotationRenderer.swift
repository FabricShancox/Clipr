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
        case .arrow:
            drawArrow(annotation.frame, in: context)
        case .freehand(let points):
            drawFreehand(points, in: context)
        case .highlighter:
            context.setAlpha(0.35)
            context.fill(annotation.frame)
        case .blur:
            // Pixelation approximation: fill with an averaged translucent box.
            // (Full pixel-sampling blur is a possible future enhancement; out of scope for v1.)
            context.setFillColor(CGColor(gray: 0.5, alpha: 0.9))
            context.fill(annotation.frame)
        case .text(let string):
            drawText(string, in: annotation.frame, color: annotation.color, context: context)
        case .stamp(let kind):
            drawStamp(kind, in: annotation.frame, color: annotation.color, context: context)
        }

        context.restoreGState()
    }

    private static func drawArrow(_ frame: CGRect, in context: CGContext) {
        let start = CGPoint(x: frame.minX, y: frame.minY)
        let end = CGPoint(x: frame.maxX, y: frame.maxY)
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 10
        let p1 = CGPoint(x: end.x - headLength * cos(angle - .pi / 6), y: end.y - headLength * sin(angle - .pi / 6))
        let p2 = CGPoint(x: end.x - headLength * cos(angle + .pi / 6), y: end.y - headLength * sin(angle + .pi / 6))
        context.move(to: end)
        context.addLine(to: p1)
        context.move(to: end)
        context.addLine(to: p2)
        context.strokePath()
    }

    private static func drawFreehand(_ points: [CGPoint], in context: CGContext) {
        guard let first = points.first else { return }
        context.move(to: first)
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private static func drawText(_ string: String, in frame: CGRect, color: RGBAColor, context: CGContext) {
        let nsColor = NSColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: nsColor,
            .font: NSFont.systemFont(ofSize: max(frame.height * 0.7, 10))
        ]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributed.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawStamp(_ kind: StampKind, in frame: CGRect, color: RGBAColor, context: CGContext) {
        let nsColor = NSColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
        guard let symbolImage = NSImage(systemSymbolName: kind.symbolName, accessibilityDescription: nil) else { return }
        let tinted = symbolImage.tinted(with: nsColor)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        tinted.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
