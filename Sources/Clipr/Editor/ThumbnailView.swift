import SwiftUI

struct ThumbnailView: View {
    let url: URL
    /// `.fill` crops to cover the tile (Recents); `.fit` shows the whole capture (Review, where the
    /// clicked spot can be anywhere in the image).
    var contentMode: ContentMode = .fill
    @State private var image: NSImage?

    init(url: URL, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
        _image = State(initialValue: ThumbnailCache.shared.image(for: url))
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
            let url = url
            let loaded = await Task.detached(priority: .userInitiated) {
                ThumbnailCache.decodeThumbnail(at: url)
            }.value
            guard let loaded else { return }
            image = loaded
            ThumbnailCache.shared.store(loaded, for: url)
        }
    }
}
