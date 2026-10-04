import SwiftUI

struct ReviewView: View {
    struct Step: Hashable {
        let url: URL
        let caption: String?
    }

    @State var steps: [Step]
    let onOpenEditor: (URL) -> Void
    let onDelete: (URL) -> Void
    let onShowInFinder: () -> Void

    /// Every card is the same width (columns share the row equally) and the same height (fixed
    /// thumbnail box, one-line filename, caption area that always reserves two lines), so the
    /// grid lines up regardless of image shape or caption length.
    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 16, alignment: .top)]
    private static let thumbnailAspect: CGFloat = 16.0 / 10.0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(steps.count == 1 ? "1 step" : "\(steps.count) steps")
                    .font(.headline)
                Spacer()
                Button("Show in Finder", action: onShowInFinder)
            }
            .padding([.horizontal, .top])
            grid
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(steps, id: \.self) { step in
                    VStack(spacing: 6) {
                        // `ThumbnailView` rather than `NSImage(contentsOf:)` inline: that read and
                        // fully decoded every step from disk on each body evaluation — including
                        // after every Delete — on the main thread.
                        Color.black.opacity(0.25)
                            .aspectRatio(Self.thumbnailAspect, contentMode: .fit)
                            .overlay(ThumbnailView(url: step.url, contentMode: .fit))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { onOpenEditor(step.url) }
                            .help("Double-click to edit")
                        Text(step.url.lastPathComponent)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        // Read-only here; editing captions is the Review sub-project.
                        Text(step.caption.map { $0.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "\\", with: "") } ?? " ")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            // A fixed two-line box, top-aligned: `reservesSpace` alone still let a
                            // one-line caption sit a couple of points off a two-line one.
                            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .top)
                        HStack {
                            Button("Edit") { onOpenEditor(step.url) }
                            Button("Delete", role: .destructive) {
                                onDelete(step.url)
                                steps.removeAll { $0.url == step.url }
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
    }
}
