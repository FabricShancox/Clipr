import Foundation

/// Guide-style step captions. Bold uses Markdown `**` so the export sub-project can render it;
/// `clean` escapes Markdown punctuation in anything taken from the UI or typed, so it can't break
/// that markup or be dropped as HTML.
enum CaptionFormatter {
    static let maxLength = 60

    private static let fieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    static func click(_ target: ClickTarget?, appName: String?) -> String {
        let app = clean(appName)
        if let target, target.role == "AXMenuItem" {
            let path = target.menuPath.compactMap { clean($0) }
            if !path.isEmpty { return "Choose **\(path.joined(separator: " ▸ "))**" }
        }
        guard let target, let label = clean(target.label) else {
            return app.map { "Click in **\($0)**" } ?? "Click"
        }
        let role = target.role ?? ""
        if fieldRoles.contains(role) { return "Click the **\(label)** field" }
        if role == "AXLink" { return "Click the **\(label)** link" }
        // Buttons, pop-ups, checkboxes, tabs and every other labelled role share this wording.
        return app.map { "Click **\(label)** in \($0)" } ?? "Click **\(label)**"
    }

    static func typing(_ text: String, fieldLabel: String?) -> String {
        let typed = clean(text) ?? ""
        if let field = clean(fieldLabel) { return "Type \"\(typed)\" in **\(field)**" }
        return "Type \"\(typed)\""
    }

    static func shortcut(_ keys: String) -> String { "Press **\(keys)**" }

    /// Trim, collapse runs of whitespace/newlines to one space, truncate to `maxLength` characters
    /// (before escaping, so escapes never get cut in half), then escape. `nil` if nothing remains.
    static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        let truncated = collapsed.count > maxLength ? String(collapsed.prefix(maxLength)) + "…" : collapsed
        return escapeMarkdown(truncated)
    }

    /// Characters CommonMark could read as markup in inline text: emphasis, code, links, images,
    /// raw HTML, entities, strikethrough, and the quote the typing caption wraps text in. Each is
    /// backslash-escaped so the text stays literal (`<div>` typed in a code editor used to vanish).
    private static let markdownPunctuation: Set<Character> = ["\\", "`", "*", "_", "[", "]", "<", ">", "&", "~", "!", "\""]

    static func escapeMarkdown(_ text: String) -> String {
        TextEscaping.backslashed(text, markdownPunctuation)
    }
}
