import Foundation

/// The five ways a reviewed session leaves Clipr. Not called `ExportFormat`: that name is the
/// image editor's PNG/JPEG "Save As…" choice.
enum GuideFormat: String, CaseIterable, Identifiable {
    case pdf, html, markdown, gif, clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return "PDF"
        case .html: return "HTML"
        case .markdown: return "Markdown"
        case .gif: return "GIF"
        case .clipboard: return "Copy as Rich Text"
        }
    }

    /// The extension of the single file this format writes; nil for Markdown (a folder) and the
    /// clipboard (no file).
    var fileExtension: String? {
        switch self {
        case .pdf: return "pdf"
        case .html: return "html"
        case .gif: return "gif"
        case .markdown, .clipboard: return nil
        }
    }

    /// The save panel's starting name: the title made safe for a filename, "Guide" when nothing
    /// usable is left of it.
    func suggestedFileName(for title: String) -> String {
        let base = FilenameGenerator.sanitizedBaseName(CaptionMarkup.stripBidi(title)) ?? "Guide"
        return fileExtension.map { "\(base).\($0)" } ?? base
    }
}
