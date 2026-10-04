import SwiftUI

struct ThumbnailView: View {
    let url: URL
    /// `.fill` crops to cover the tile (Recents); `.fit` shows the whole capture (Review, where the
    /// clicked spot can be anywhere in the image).
    var contentMode: ContentMode = .fill
    var maxPixelSize: Int = ThumbnailCache.maxPixelSize
    @State private var image: NSImage?

    init(url: URL, contentMode: ContentMode = .fill, maxPixelSize: Int = ThumbnailCache.maxPixelSize) {
        self.url = url
        self.contentMode = contentMode
        self.maxPixelSize = maxPixelSize
        _image = State(initialValue: ThumbnailCache.shared.image(for: url, maxPixelSize: maxPixelSize))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(Color(red: 0x1C / 255.0, green: 0x25 / 255.0, blue: 0x2E / 255.0))
            }
        }
        .task(id: url) {
            guard image == nil else { return }
            // Detached so the decode doesn't run on the main actor, which `.task` would otherwise
            // inherit — this used to be a full-resolution decode blocking the UI per tile.
            let url = url, size = maxPixelSize
            let loaded = await Task.detached(priority: .userInitiated) {
                ThumbnailCache.decodeThumbnail(at: url, maxPixelSize: size)
            }.value
            // A view whose URL changed (or that went away) mid-decode has its task cancelled; its
            // late result may be of a file that's since been replaced, so it isn't cached.
            guard let loaded, !Task.isCancelled else { return }
            image = loaded
            ThumbnailCache.shared.store(loaded, for: url, maxPixelSize: size)
        }
    }
}
