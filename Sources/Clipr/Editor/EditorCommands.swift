import Cocoa

/// Bridges the standard Edit-menu keys (⌘C, ⌘X, ⌘V, ⌘A) from `EditorWindowController` into
/// `EditorView`, which owns the annotations and selection they act on.
///
/// These keys are already claimed by the app's Edit menu, which routes them down the responder
/// chain so text fields work. With no text field focused, nothing on the canvas side of that
/// chain answers, so the keys did nothing. The controller intercepts them for the editor window
/// only while no text is being edited and hands them here; the view registers `perform` when it
/// appears (and again on every content-view rebuild).
final class EditorCommands {
    enum Action { case copy, cut, paste, selectAll }

    var perform: ((Action) -> Void)?

    /// Maps a key-down to an action, or `nil` for anything else — including the same letters with
    /// extra modifiers, which belong to other shortcuts (⇧⌘C is Copy-image).
    static func action(for event: NSEvent) -> Action? {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else { return nil }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": return .copy
        case "x": return .cut
        case "v": return .paste
        case "a": return .selectAll
        default: return nil
        }
    }
}
