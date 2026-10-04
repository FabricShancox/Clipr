// Sources/Clipr/AdvancedMode/Export/GuideImages.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The outcome of rendering one step image.
struct GuideImageRender {
    /// Nil when the image is missing or won't decode.
    let image: GuideImage?
    /// The step's annotation sidecar exists but couldn't be read. `image` is then nil: the raw capture
    /// may hold content a redaction was covering, so it is never exported.
    let sidecarDamaged: Bool
}

/// Turns a step's raw PNG into the picture an export shows: annotations flattened on (as Review
/// and the editor show it), scaled down to what a guide needs, and encoded small enough to embed.
/// Safe to call off the main thread: everything is drawn into explicit CGContexts.
enum GuideImages {
    /// A Full-width step's width in pixels; sized steps get their share of it.
    static let fullPixelWidth = 1600
    /// Close-ups sit at 30% of the content width.
    static let zoomPixelWidth = 480
    /// Above this a PNG is re-encoded as JPEG, so a photo-like screenshot doesn't bloat the guide.
    static let jpegThreshold = 1_500_000
    static let jpegQuality = 0.85

    static func maxPixelWidth(for size: ImageSize) -> Int {
        Int((CGFloat(fullPixelWidth) * size.widthFraction).rounded())
    }

    static func render(_ ref: GuideImageRef, maxPixelWidth: Int, jpegThreshold: Int = GuideImages.jpegThreshold) -> GuideImageRender {
        // A guide renders dozens of full-size captures in a row; the pool frees each one's
        // bitmaps before the next instead of at the end of the whole export.
        autoreleasepool {
            if case .closeUp(let source) = ref { return renderCloseUp(source, maxPixelWidth: maxPixelWidth, jpegThreshold: jpegThreshold) }
            guard case .file(let url) = ref, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  CGImageSourceGetCount(source) > 0, UntrustedImageLimits.isSafeToDecode(source) else {
                return GuideImageRender(image: nil, sidecarDamaged: false)
            }
            // Too large to parse safely is treated like unreadable: it may hold a redaction.
            if UntrustedImageLimits.sidecarTooLarge(forRaw: url) { return GuideImageRender(image: nil, sidecarDamaged: true) }
            var annotations: [AnnotationObject] = []
            switch StorageManager(baseFolder: url.deletingLastPathComponent()).readAnnotations(rawURL: url) {
            case .loaded(let loaded): annotations = loaded
            case .corrupt: return GuideImageRender(image: nil, sidecarDamaged: true)
            case .missing: break
            }
            let scaled: CGImage?
            if annotations.isEmpty {
                scaled = thumbnail(source, maxPixelWidth: maxPixelWidth)
            } else {
                // Annotations are in points on the full-size image, so flatten first, then shrink.
                guard let base = NSImage(contentsOf: url), base.bitmap != nil else {
                    return GuideImageRender(image: nil, sidecarDamaged: false)
                }
                let flat = AnnotationRenderer.flatten(base: base, annotations: annotations)
                scaled = flat.bitmap.flatMap { downsampled($0, maxPixelWidth: maxPixelWidth) }
            }
            guard let scaled else { return GuideImageRender(image: nil, sidecarDamaged: false) }
            return GuideImageRender(image: encode(scaled, jpegThreshold: jpegThreshold), sidecarDamaged: false)
        }
    }

    /// The close-up cut from the step as the guide shows it (annotations flattened, crops applied),
    /// with the same crop capture uses. Nil — so the export leaves it out and warns — whenever the
    /// click point can't be trusted to still mark the same spot, or the annotations can't be read
    /// (a redaction might be among them).
    private static func renderCloseUp(_ source: CloseUpSource, maxPixelWidth: Int, jpegThreshold: Int) -> GuideImageRender {
        let none = GuideImageRender(image: nil, sidecarDamaged: false)
        guard UntrustedImageLimits.isSafeToDecode(source.step), UntrustedImageLimits.isSafeToDecode(source.capturedZoom),
              !UntrustedImageLimits.sidecarTooLarge(forRaw: source.step),
              let base = NSImage(contentsOf: source.step), base.bitmap != nil,
              let captured = NSImage(contentsOf: source.capturedZoom) else { return none }
        let annotations: [AnnotationObject]
        switch StorageManager(baseFolder: source.step.deletingLastPathComponent()).readAnnotations(rawURL: source.step) {
        case .loaded(let loaded): annotations = loaded
        case .missing: annotations = []
        case .corrupt: return none
        }
        guard let closeUp = StepZoom.closeUp(base: base, annotations: annotations, clickPoint: source.clickPoint, captured: captured),
              let bitmap = closeUp.bitmap, let scaled = downsampled(bitmap, maxPixelWidth: maxPixelWidth) else { return none }
        return GuideImageRender(image: encode(scaled, jpegThreshold: jpegThreshold), sidecarDamaged: false)
    }

    /// Decodes straight to the target size so a huge capture is never held at full resolution.
    /// ImageIO bounds the *long* side, so the cap is converted from a width to that.
    private static func thumbnail(_ source: CGImageSource, maxPixelWidth: Int) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return nil }
        guard maxPixelWidth > 0, width > maxPixelWidth else {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        // Rounded up so the width is never short of the cap; `downsampled` trims any excess pixel.
        let longSide = Int((Double(max(width, height)) * Double(maxPixelWidth) / Double(width)).rounded(.up))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return downsampled(image, maxPixelWidth: maxPixelWidth)
    }

    /// `image` no wider than `maxPixelWidth` pixels (never enlarged), aspect ratio kept. Pixels,
    /// not points: a Retina capture is twice as many pixels as its point size.
    static func downsampled(_ image: CGImage, maxPixelWidth: Int) -> CGImage? {
        guard maxPixelWidth > 0, image.width > maxPixelWidth else { return image }
        let width = maxPixelWidth
        let height = max(1, Int((CGFloat(image.height) * CGFloat(width) / CGFloat(image.width)).rounded()))
        guard let context = BitmapContext.rgb(width: width, height: height) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// PNG, or JPEG when the PNG would be larger than `jpegThreshold` bytes.
    static func encode(_ image: CGImage, jpegThreshold: Int = GuideImages.jpegThreshold) -> GuideImage? {
        guard let png = ImageEncoding.data(image, type: .png) else { return nil }
        let pngImage = GuideImage(data: png, pixelWidth: image.width, pixelHeight: image.height, kind: .png)
        guard png.count > jpegThreshold else { return pngImage }
        guard let opaque = onWhite(image),
              let jpeg = ImageEncoding.data(opaque, type: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: jpegQuality])
        else { return pngImage }
        return GuideImage(data: jpeg, pixelWidth: image.width, pixelHeight: image.height, kind: .jpeg)
    }

    /// JPEG has no alpha: transparent areas (a canvas the editor enlarged) would turn black.
    private static func onWhite(_ image: CGImage) -> CGImage? {
        guard let context = BitmapContext.rgb(width: image.width, height: image.height, opaque: true) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
