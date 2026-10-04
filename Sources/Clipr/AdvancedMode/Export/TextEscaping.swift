import Foundation

/// Shared mechanics for Markdown escaping. Which characters need escaping differs by context (an
/// inline caption versus a heading line), so each caller passes its own set.
enum TextEscaping {
    /// `text` with a backslash before every character in `special`.
    static func backslashed(_ text: String, _ special: Set<Character>) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            if special.contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }
}
