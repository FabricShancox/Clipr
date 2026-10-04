import AppKit

/// Whether the focused element is a password field. `unknown` whenever Accessibility couldn't
/// say for sure (no focused element, timeout, any other read error, or anything
/// `TypingInputPolicy` doesn't trust) — typing steps treat it like `secure`, so a failed read can
/// never let a password through.
enum FieldSecurity: Equatable {
    case secure, notSecure, unknown
}
