import SwiftUI

/// The Recent-captures sidebar. See `EditorView.swift`'s header for how this file relates to the
/// rest of the type.
extension EditorView {
    var sidebar: some View {
        VStack(spacing: 12) {
            Text("RECENT")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .foregroundColor(EditorColors.t2)
                .padding(.top, 16)
            OverlayScrollView {
                VStack(spacing: 6) {
                    ForEach(visibleRecents, id: \.self) { url in
                        recentThumbnail(for: url)
                    }
                }
                .padding(.horizontal, 4)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 135)
        .background(EditorColors.s2)
    }

    func recentThumbnail(for url: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            Button { onOpenCapture(url, annotations) } label: {
                VStack(spacing: 6) {
                    ThumbnailView(url: url)
                        .frame(width: 80, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Text(relativeLabel(for: url))
                        .font(.system(size: 10))
                        .foregroundColor(EditorColors.t2)
                        .lineLimit(1)
                }
                .padding(6)
                .background(url == currentURL ? EditorColors.accent12 : Color.clear)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .help(url.lastPathComponent)

            // Deleting the capture that's currently open would pull the rug out from under this
            // whole window (its image, its autosave target), so that one has no delete button.
            if url != currentURL {
                Button {
                    onDeleteCapture(url) { deletedRecentURLs.insert(url) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(EditorColors.t2)
                        .background(Circle().fill(EditorColors.s2))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: 2)
                .help("Move this capture to the Trash")
            }
        }
    }

    func relativeLabel(for url: URL) -> String {
        guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            return url.lastPathComponent
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
