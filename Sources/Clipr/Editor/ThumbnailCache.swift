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
    /// Review's Large and Guide layouts show steps several hundred points wide; 320px would be
    /// visibly soft there.
    static let largePixelSize = 1600
    private static let knownSizes = [maxPixelSize, largePixelSize]

    /// Keyed by URL *and* decode size, so a Large-layout decode never replaces the small one the
    /// editor sidebar uses (or the other way round).
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        // ~96MB: hundreds of small thumbnails, or a screenful of Review's large decodes
        // (~6MB each), but bounded — NSCache evicts beyond this and under memory pressure.
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    private static func key(_ url: URL, _ size: Int) -> NSString { "\(size)|\(url.absoluteString)" as NSString }

    func image(for url: URL, maxPixelSize: Int = ThumbnailCache.maxPixelSize) -> NSImage? {
        cache.object(forKey: Self.key(url, maxPixelSize))
    }

    func store(_ image: NSImage, for url: URL, maxPixelSize: Int = ThumbnailCache.maxPixelSize) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: Self.key(url, maxPixelSize), cost: cost)
    }

    /// Review drops a step's entry after the image editor closes, so the edited image is decoded
    /// again instead of the stale one being shown.
    func remove(_ url: URL) {
        for size in Self.knownSizes { cache.removeObject(forKey: Self.key(url, size)) }
    }

    /// Decodes `url` downsampled, without ever materialising the full-size image.
    ///
    /// `ImageDecoder` subsamples during decode, so a 24-megapixel capture never costs 96MB just
    /// to produce a tile. Deliberately not `@MainActor` — callers run it off the main thread,
    /// since the previous full decode happened on it.
    static func decodeThumbnail(at url: URL, maxPixelSize: Int = ThumbnailCache.maxPixelSize) -> NSImage? {
        guard let cgImage = ImageDecoder.thumbnail(at: url, maxPixelSize: maxPixelSize) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
