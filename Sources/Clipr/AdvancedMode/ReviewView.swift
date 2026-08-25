import SwiftUI

struct ReviewView: View {
    @State var stepURLs: [URL]
    let onOpenEditor: (URL) -> Void
    let onDelete: (URL) -> Void

    private let columns = [GridItem(.adaptive(minimum: 160))]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(stepURLs, id: \.self) { url in
                    VStack {
                        if let image = NSImage(contentsOf: url) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 100)
                        }
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
        .frame(minWidth: 500, minHeight: 400)
    }
}
