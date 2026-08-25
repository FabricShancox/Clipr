import Cocoa

/// Session-lifetime decoded-thumbnail cache, keyed by file URL. `EditorWindowController` swaps
/// in a brand new `EditorView` (and every one of its child `ThumbnailView`s) on every Recent
/// click and every crop/resize, so a per-view `@State` cache alone still means every thumbnail
/// the user has already seen decodes from disk and flashes its placeholder again on every one of
/// those content-view rebuilds. A cache that outlives any single `EditorView` instance is what
/// actually stops that: `ThumbnailView.init` seeds its `@State` from here synchronously, so an
/// already-seen URL never shows the placeholder at all.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private var images: [URL: NSImage] = [:]

    func image(for url: URL) -> NSImage? { images[url] }
    func store(_ image: NSImage, for url: URL) { images[url] = image }
}
