import SwiftUI

struct ThumbnailView: View {
    let url: URL
    @State private var image: NSImage?

    init(url: URL) {
        self.url = url
        _image = State(initialValue: ThumbnailCache.shared.image(for: url))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color(red: 0x1C / 255.0, green: 0x25 / 255.0, blue: 0x2E / 255.0))
            }
        }
        .task(id: url) {
            guard image == nil else { return }
            guard let loaded = NSImage(contentsOf: url) else { return }
            image = loaded
            ThumbnailCache.shared.store(loaded, for: url)
        }
    }
}
