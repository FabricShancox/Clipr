import Cocoa

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
