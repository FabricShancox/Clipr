import Cocoa

/// Pixelation for the redaction (`.blur`) tool, shared by the on-screen preview
/// (`AnnotationOverlayShape`) and the flattened export (`AnnotationRenderer`) so what the editor
/// shows is exactly what gets written.
///
/// The tool used to paint a flat `gray 0.5, alpha 0.9` box. That is not redaction: a tenth of
/// every underlying pixel survived into the exported file, so raising the contrast on a
/// "redacted" screenshot could bring the original text back. Real pixelation destroys the
/// information instead of dimming it, and the result is fully opaque.
enum Pixelation {
    /// Block edge length for a region, in the same units as the region.
    ///
    /// Deliberately coarse: a redaction is usually dragged tightly around a line of text, so the
    /// region's short edge is roughly the glyph height. Blocks much smaller than that leave the
    /// letter shapes legible in the block pattern — verified by eye at `min/8`, where a redacted
    /// password was still largely readable. Only a handful of blocks across the short edge
    /// destroys the glyph structure rather than merely coarsening it.
    static func blockSize(for rect: CGRect) -> CGFloat {
        max(16, min(rect.width, rect.height) / 3)
    }

    /// Averages `rect` of `source` down to blocks and returns just that region, pixelated.
    ///
    /// Works by drawing the region into a context a fraction of its size — which averages each
    /// block's pixels into one — then scaling that back up with interpolation off, giving hard
    /// blocks rather than a smooth blur. `rect` is in `source`'s pixel space, top-left origin,
    /// matching `CGImage.cropping(to:)`.
    static func pixelatedRegion(of source: CGImage, in rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let region = rect.integral.intersection(bounds)
        guard !region.isNull, region.width >= 1, region.height >= 1,
              let cropped = source.cropping(to: region) else { return nil }

        let block = blockSize(for: region)
        let smallWidth = max(1, Int((region.width / block).rounded(.down)))
        let smallHeight = max(1, Int((region.height / block).rounded(.down)))

        guard let small = CGContext(
            data: nil, width: smallWidth, height: smallHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        small.interpolationQuality = .medium // averages the block being collapsed
        small.draw(cropped, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        guard let averaged = small.makeImage() else { return nil }

        guard let full = CGContext(
            data: nil, width: Int(region.width), height: Int(region.height), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Off, so each averaged pixel becomes a hard square instead of being smoothed back into
        // something with recoverable detail.
        full.interpolationQuality = .none
        full.draw(averaged, in: CGRect(x: 0, y: 0, width: region.width, height: region.height))
        return full.makeImage()
    }
}

/// Pixelated redaction previews for the editor canvas, so they aren't recomputed on every body
/// evaluation.
///
/// `AnnotationOverlayShape` is re-evaluated on every hover and every drag frame, and each
/// evaluation used to fetch the bitmap, crop it and run two `CGContext`s for every redaction on
/// the canvas — noticeable lag on large Retina captures with several redactions. Entries are
/// keyed by the region and checked against the image they were made from (held weakly), so a
/// different capture at the same address can't be served a stale preview.
final class PixelatedPreviewCache {
    static let shared = PixelatedPreviewCache()

    private final class Entry {
        weak var image: NSImage?
        let pixelated: CGImage
        let visible: CGRect
        init(image: NSImage, pixelated: CGImage, visible: CGRect) {
            self.image = image
            self.pixelated = pixelated
            self.visible = visible
        }
    }

    private let cache: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 64
        return cache
    }()

    /// The pixelated on-canvas part of `displayFrame` (image points, top-left origin) and where
    /// to draw it, or `nil` if nothing of it is on the canvas or it couldn't be sampled.
    func preview(of image: NSImage, in displayFrame: CGRect) -> (CGImage, CGRect)? {
        let visible = displayFrame.intersection(CGRect(origin: .zero, size: image.size))
        guard !visible.isNull, visible.width >= 1, visible.height >= 1 else { return nil }
        let key = "\(ObjectIdentifier(image).hashValue)|\(visible.origin.x),\(visible.origin.y),\(visible.width),\(visible.height)" as NSString
        if let entry = cache.object(forKey: key), entry.image === image {
            return (entry.pixelated, entry.visible)
        }
        guard let cg = image.bitmap,
              let pixelated = Pixelation.pixelatedRegion(of: cg, in: visible.scaled(by: image.pixelScale)) else { return nil }
        cache.setObject(Entry(image: image, pixelated: pixelated, visible: visible), forKey: key)
        return (pixelated, visible)
    }
}
