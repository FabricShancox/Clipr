import Foundation

/// One key press, already decoded off the event tap so this file stays free of CGEvent.
struct KeyInput: Equatable {
    /// As typed (with Shift/Option applied).
    var characters: String
    /// `charactersIgnoringModifiers`, used to name shortcuts.
    var baseCharacters: String
    var keyCode: UInt16
    var modifiers: KeyModifiers
    /// macOS secure input was on, or the focused element is a password field.
    var isSecure: Bool
}
