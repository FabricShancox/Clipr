import SwiftUI

struct ReviewView: View {
    @State var stepURLs: [URL]
    let onOpenEditor: (URL) -> Void
    let onDelete: (URL) -> Void
    let onShowInFinder: (() -> Void)?

    private let columns = [GridItem(.adaptive(minimum: 160))]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(stepURLs.count == 1 ? "1 step" : "\(stepURLs.count) steps")
                    .font(.headline)
                Spacer()
                if let onShowInFinder {
                    Button("Show in Finder", action: onShowInFinder)
                }
            }
            .padding([.horizontal, .top])
            grid
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(stepURLs, id: \.self) { url in
                    VStack {
                        // `ThumbnailView` rather than `NSImage(contentsOf:)` inline: that read and
                        // fully decoded every step from disk on each body evaluation — including
                        // after every Delete — on the main thread.
                        ThumbnailView(url: url)
                            .frame(height: 100)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { onOpenEditor(url) }
                            .help("Double-click to edit")
                        Text(url.lastPathComponent).font(.caption)
                        HStack {
                            Button("Edit") { onOpenEditor(url) }
                            Button("Delete", role: .destructive) {
                                onDelete(url)
                                stepURLs.removeAll { $0 == url }
                            }
                        }
                    }
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
    }
}
