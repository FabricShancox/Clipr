import Foundation

/// Renders a caption's inline markdown (bold, italics) for display.
enum CaptionText {
    /// Captions are partly built from other apps' Accessibility labels, so they are untrusted: a
    /// label like `[x](https://evil)` or `<file:///…>` must not become a clickable link in Review.
    /// Emphasis is kept; every link and image URL is stripped.
    static func rendered(_ markdown: String) -> AttributedString {
        guard var text = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return AttributedString(markdown) }
        for run in text.runs where run.link != nil || run.imageURL != nil {
            text[run.range].link = nil
            text[run.range].imageURL = nil
        }
        return text
    }
}
