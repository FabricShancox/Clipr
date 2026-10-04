// Sources/Clipr/AdvancedMode/Export/GuideImages.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The outcome of rendering one step image.
struct GuideImageRender {
    /// Nil when the image is missing or won't decode.
    let image: GuideImage?
    /// The step's annotation sidecar exists but couldn't be read, so `image` is the raw capture.
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
        guard case .file(let url) = ref, let base = NSImage(contentsOf: url), base.bitmap != nil else {
            return GuideImageRender(image: nil, sidecarDamaged: false)
        }
        var annotations: [AnnotationObject] = []
        var damaged = false
        switch StorageManager(baseFolder: url.deletingLastPathComponent()).readAnnotations(rawURL: url) {
        case .loaded(let loaded): annotations = loaded
        case .corrupt: damaged = true
        case .missing: break
        }
        let flat = annotations.isEmpty ? base : AnnotationRenderer.flatten(base: base, annotations: annotations)
        guard let bitmap = flat.bitmap, let scaled = downsampled(bitmap, maxPixelWidth: maxPixelWidth) else {
            return GuideImageRender(image: nil, sidecarDamaged: damaged)
        }
        return GuideImageRender(image: encode(scaled, jpegThreshold: jpegThreshold), sidecarDamaged: damaged)
    }

    /// `image` no wider than `maxPixelWidth` pixels (never enlarged), aspect ratio kept. Pixels,
    /// not points: a Retina capture is twice as many pixels as its point size.
    static func downsampled(_ image: CGImage, maxPixelWidth: Int) -> CGImage? {
        guard maxPixelWidth > 0, image.width > maxPixelWidth else { return image }
        let width = maxPixelWidth
        let height = max(1, Int((CGFloat(image.height) * CGFloat(width) / CGFloat(image.width)).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// PNG, or JPEG when the PNG would be larger than `jpegThreshold` bytes.
    static func encode(_ image: CGImage, jpegThreshold: Int = GuideImages.jpegThreshold) -> GuideImage? {
        guard let png = encoded(image, as: .png, properties: [:]) else { return nil }
        let pngImage = GuideImage(data: png, pixelWidth: image.width, pixelHeight: image.height, kind: .png)
        guard png.count > jpegThreshold else { return pngImage }
        guard let opaque = onWhite(image),
              let jpeg = encoded(opaque, as: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: jpegQuality])
        else { return pngImage }
        return GuideImage(data: jpeg, pixelWidth: image.width, pixelHeight: image.height, kind: .jpeg)
    }

    private static func encoded(_ image: CGImage, as type: UTType, properties: [CFString: Any]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// JPEG has no alpha: transparent areas (a canvas the editor enlarged) would turn black.
    private static func onWhite(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
