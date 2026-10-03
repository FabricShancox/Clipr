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

    private let columns = [GridItem(.adaptive(minimum: 160))]

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
                    VStack {
                        // `ThumbnailView` rather than `NSImage(contentsOf:)` inline: that read and
                        // fully decoded every step from disk on each body evaluation — including
                        // after every Delete — on the main thread.
                        ThumbnailView(url: step.url)
                            .frame(height: 100)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { onOpenEditor(step.url) }
                            .help("Double-click to edit")
                        Text(step.url.lastPathComponent).font(.caption)
                        if let caption = step.caption {
                            // Read-only here; editing captions is the Review sub-project.
                            Text(caption.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "\\", with: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        HStack {
                            Button("Edit") { onOpenEditor(step.url) }
                            Button("Delete", role: .destructive) {
                                onDelete(step.url)
                                steps.removeAll { $0.url == step.url }
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
