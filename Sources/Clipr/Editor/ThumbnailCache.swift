import Cocoa

/// Session-lifetime decoded-thumbnail cache, keyed by file URL. `EditorWindowController` swaps
/// in a brand new `EditorView` (and every one of its child `ThumbnailView`s) on every Recent
/// click and every crop/resize, so a per-view `@State` cache alone still means every thumbnail
/// the user has already seen decodes from disk and flashes its placeholder again on every one of
/// those content-view rebuilds. A cache that outlives any single `EditorView` instance is what
/// actually stops that: `ThumbnailView.init` seeds its `@State` from here synchronously, so an
/// already-seen URL never shows the placeholder at all.
///
/// Backed by `NSCache` with a cost limit rather than a plain dictionary. The entries used to be
/// full-resolution decodes held for the whole session — twenty 6000x4000 captures is well over a
/// gigabyte of resident memory to draw twenty 80x56 tiles — with no eviction. Entries are now
/// downsampled at decode time and the cache can drop them under memory pressure.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    /// Longest edge to decode to. Comfortably covers the 80x56 tile at 2x, with headroom so the
    /// tiles stay sharp if the sidebar ever grows.
    static let maxPixelSize = 320

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        // ~32MB: hundreds of thumbnails at this size, but bounded.
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    func image(for url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    func store(_ image: NSImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    /// Review drops a step's entry after the image editor closes, so the edited image is decoded
    /// again instead of the stale one being shown.
    func remove(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    /// Decodes `url` downsampled, without ever materialising the full-size image.
    ///
    /// `CGImageSourceCreateThumbnailAtIndex` does the subsampling during decode, so a 24-megapixel
    /// capture never costs 96MB just to produce a tile. Deliberately not `@MainActor` — callers
    /// run it off the main thread, since the previous full decode happened on it.
    static func decodeThumbnail(at url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
