import Foundation

/// Step captions are inline Markdown partly built from other apps' Accessibility labels, so they
/// are untrusted. Every export keeps bold, italic and code and turns everything else — links,
/// images, autolinks, raw HTML — into plain text, the rule `CaptionText` applies in Review.
enum CaptionMarkup {
    /// One stretch of caption text and the emphasis kept on it.
    struct Span: Equatable {
        var text: String
        var bold = false
        var italic = false
        var code = false
    }

    /// The caption parsed into spans. Line breaks become spaces, since every format shows a caption
    /// as a one-line heading (a newline would end a Markdown heading early). Raw HTML tags are
    /// dropped and the text between them kept. Empty when nothing visible is left.
    static func spans(_ markdown: String?) -> [Span] {
        guard let markdown else { return [] }
        let flattened = markdown.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard let parsed = try? AttributedString(
            markdown: flattened,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return flattened.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [Span(text: flattened)]
        }
        var result: [Span] = []
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.inlineHTML) { continue }
            // The parser decodes entities such as "&#10;" into real newlines after the flattening
            // above, so line breaks are replaced again here, run by run; otherwise a caption could
            // escape its heading line in Markdown.
            let text = stripBidi(String(parsed[run.range].characters.map { $0.isNewline ? " " : $0 }))
            guard !text.isEmpty else { continue }
            let span = Span(text: text, bold: intent.contains(.stronglyEmphasized),
                            italic: intent.contains(.emphasized), code: intent.contains(.code))
            // A link's text arrives as its own run; merging it back keeps the output tidy.
            if let last = result.last, last.bold == span.bold, last.italic == span.italic, last.code == span.code {
                result[result.count - 1].text += span.text
            } else {
                result.append(span)
            }
        }
        if result.allSatisfy({ $0.text.trimmingCharacters(in: .whitespaces).isEmpty }) { return [] }
        return result
    }

    /// The caption as HTML: `<strong>`, `<em>` and `<code>` only, every character of text escaped.
    static func html(_ markdown: String?, fallbackNumber: Int) -> String {
        let parts = spans(markdown)
        guard !parts.isEmpty else { return "Step \(fallbackNumber)" }
        return parts.map { span in
            var text = escapeHTML(span.text)
            if span.code { text = "<code>\(text)</code>" }
            if span.italic { text = "<em>\(text)</em>" }
            if span.bold { text = "<strong>\(text)</strong>" }
            return text
        }.joined()
    }

    /// The caption as Markdown that can't turn into a link, image or HTML wherever it's rendered.
    static func markdown(_ markdown: String?, fallbackNumber: Int) -> String {
        let parts = spans(markdown)
        guard !parts.isEmpty else { return "Step \(fallbackNumber)" }
        return parts.map { span in
            var text = span.code ? codeSpan(span.text) : escapeMarkdown(span.text)
            if span.italic { text = "*\(text)*" }
            if span.bold { text = "**\(text)**" }
            return text
        }.joined()
    }

    /// The caption's words alone, for the GIF's caption band.
    static func plainText(_ markdown: String?, fallbackNumber: Int) -> String {
        let parts = spans(markdown)
        return parts.isEmpty ? "Step \(fallbackNumber)" : parts.map(\.text).joined()
    }

    /// Bidirectional controls (U+202A-202E, U+2066-2069) can reorder the text around a caption or
    /// title; they are removed from everything exported.
    static func stripBidi(_ text: String) -> String {
        String(text.unicodeScalars.filter { !(0x202A...0x202E).contains($0.value) && !(0x2066...0x2069).contains($0.value) })
    }

    static func escapeHTML(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in stripBidi(text) {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }

    /// Backslash-escapes every character that could start Markdown syntax inside a heading line.
    /// `*` is included alongside the spec's list: captions carry literal asterisks (CaptionFormatter
    /// escapes them in UI labels) that would otherwise turn into emphasis.
    static func escapeMarkdown(_ text: String) -> String {
        TextEscaping.backslashed(stripBidi(text), headingSpecial)
    }

    private static let headingSpecial: Set<Character> = ["\\", "`", "*", "_", "[", "]", "<", ">", "~", "&", "#"]

    /// A code span whose fence is longer than any run of backticks inside it, so the code can't
    /// close its own span.
    private static func codeSpan(_ text: String) -> String {
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: longest + 1)
        let pad = text.hasPrefix("`") || text.hasSuffix("`") ? " " : ""
        return fence + pad + text + pad + fence
    }
}
