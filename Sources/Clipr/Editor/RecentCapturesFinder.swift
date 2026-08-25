import Foundation

/// Recent top-level captures in a save folder, newest first, for the editor sidebar. Sorted
/// purely by modification date — the currently-open one is never pinned to the front, only
/// highlighted (`EditorView.recentThumbnail`'s `url == currentURL` check) — so clicking between
/// different Recent thumbnails never reshuffles the list out from under the user. Excludes
/// `_edited` companions: those are auto-save's output, not a distinct capture to browse to.
func recentCaptures(in folder: URL, limit: Int = 20) -> [URL] {
    guard let entries = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
    ) else { return [] }

    let pngs = entries.filter { $0.pathExtension.lowercased() == "png" && !$0.lastPathComponent.hasSuffix("_edited.png") }
    let sorted = pngs.sorted { a, b in
        let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        return dateA > dateB
    }
    return Array(sorted.prefix(limit))
}
