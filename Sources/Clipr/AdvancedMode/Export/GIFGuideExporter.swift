// Sources/Clipr/AdvancedMode/Export/GIFGuideExporter.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// An animated slideshow of the guide for chat and READMEs: one frame per step, the step image
/// centred on a fixed canvas with its caption in a band underneath, looping forever.
enum GIFGuideExporter {
    static let maxCanvasWidth = 1000
    /// Keeps the caption band readable when every step is a small crop.
    static let minCanvasWidth = 480
    static let captionBandHeight = 72
    /// A tall capture would otherwise make a GIF many thousands of pixels high; such images are
    /// scaled down to fit instead, so the whole canvas (image area plus caption band) stays within this.
    static let maxCanvasHeight = 1200
    /// Image-area height when no step has an image at all.
    static let placeholderHeight = 400

    enum GIFError: Error { case cannotCreate, encodeFailed }

    static func clampedFrameSeconds(_ seconds: Double) -> Double {
        min(max(seconds, ExportOptions.gifFrameRange.lowerBound), ExportOptions.gifFrameRange.upperBound)
    }

    /// One canvas for every frame, so the GIF doesn't jump: as wide as the widest image (within
    /// limits) and as tall as the tallest image at that width, plus the caption band.
    static func canvasSize(for images: [GuideImage?]) -> CGSize {
        let present = images.compactMap { $0 }
        let widest = present.map(\.pixelWidth).max() ?? maxCanvasWidth
        let width = min(maxCanvasWidth, max(minCanvasWidth, widest))
        let maxImageHeight = maxCanvasHeight - captionBandHeight
        let tallest = present.map { fittedSize($0, width: width, maxHeight: maxImageHeight).height }.max() ?? placeholderHeight
        return CGSize(width: width, height: tallest + captionBandHeight)
    }

    /// `image` scaled down (never up, aspect kept) to fit `width` and, when given, `maxHeight`.
    static func fittedSize(_ image: GuideImage, width: Int, maxHeight: Int = .max) -> (width: Int, height: Int) {
        let scale = min(1, Double(width) / Double(image.pixelWidth), Double(maxHeight) / Double(image.pixelHeight))
        guard scale < 1 else { return (image.pixelWidth, image.pixelHeight) }
        return (max(1, Int((Double(image.pixelWidth) * scale).rounded())),
                max(1, Int((Double(image.pixelHeight) * scale).rounded())))
    }

    static func export(_ doc: GuideDocument, images: RenderedImages, frameSeconds: Double, to url: URL) throws {
        let frames = doc.steps.map { images.steps[$0.number] }
        let canvas = canvasSize(for: frames)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, doc.steps.count, nil) else {
            throw GIFError.cannotCreate
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let delay = clampedFrameSeconds(frameSeconds)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay],
        ] as CFDictionary
        for (step, image) in zip(doc.steps, frames) {
            let caption = CaptionMarkup.plainText(step.caption, fallbackNumber: step.number)
            guard let frame = renderFrame(image, caption: caption, canvas: canvas) else { throw GIFError.encodeFailed }
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { throw GIFError.encodeFailed }
    }

    static func renderFrame(_ image: GuideImage?, caption: String, canvas: CGSize) -> CGImage? {
        let width = Int(canvas.width)
        guard let context = CGContext(
            data: nil, width: width, height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let band = CGFloat(captionBandHeight)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: canvas))
        // CG is y-up: the caption band is at the bottom, so the image area starts above it.
        let imageArea = CGRect(x: 0, y: band, width: canvas.width, height: canvas.height - band)
        if let image, let source = CGImageSourceCreateWithData(image.data as CFData, nil),
           let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let fitted = fittedSize(image, width: width, maxHeight: Int(imageArea.height))
            context.interpolationQuality = .high
            context.draw(decoded, in: CGRect(
                x: (canvas.width - CGFloat(fitted.width)) / 2,
                y: imageArea.minY + (imageArea.height - CGFloat(fitted.height)) / 2,
                width: CGFloat(fitted.width), height: CGFloat(fitted.height)
            ))
        } else {
            let box = imageArea.insetBy(dx: 24, dy: 24)
            context.setFillColor(CGColor(gray: 0.95, alpha: 1))
            context.fill(box)
            drawText("Image unavailable", in: box, size: 18, color: NSColor(white: 0.55, alpha: 1), context: context)
        }
        context.setFillColor(CGColor(gray: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvas.width, height: band))
        drawText(caption, in: CGRect(x: 16, y: 0, width: canvas.width - 32, height: band), size: 20,
                 color: NSColor(white: 0.11, alpha: 1), context: context)
        return context.makeImage()
    }

    /// One centred line, truncated with "…" if it doesn't fit.
    private static func drawText(_ text: String, in rect: CGRect, size: CGFloat, color: NSColor, context: CGContext) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
        let lineHeight = ceil(attributed.size().height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributed.draw(with: CGRect(x: rect.minX, y: rect.midY - lineHeight / 2, width: rect.width, height: lineHeight),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        NSGraphicsContext.restoreGraphicsState()
    }
}
