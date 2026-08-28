import SwiftUI

/// Number-key tool shortcuts. See `EditorView.swift`'s header for how this file relates to the
/// rest of the type.
extension EditorView {
    /// Zero-size, invisible buttons whose sole purpose is registering a `.keyboardShortcut` —
    /// SwiftUI has no lower-ceremony way to bind a bare key to an action outside a visible
    /// control. Each is `.disabled` while any text field is being edited (`isTextEntryActive`
    /// covers both a text annotation and the header's rename field), which also disables its
    /// keyboard shortcut, so typing "1"-"9" types those characters instead of switching tools out
    /// from under the user.
    var toolShortcuts: some View {
        let editing = isTextEntryActive
        return Group {
            shortcutButton("1", tool: .select, editing: editing)
            shortcutButton("2", tool: .rectangle, editing: editing)
            shortcutButton("3", tool: .ellipse, editing: editing)
            shortcutButton("4", tool: .arrow, editing: editing)
            shortcutButton("5", tool: .freehand, editing: editing)
            shortcutButton("6", tool: .text, editing: editing)
            shortcutButton("7", tool: numberTool, editing: editing)
            shortcutButton("8", tool: .highlighter, editing: editing)
            shortcutButton("9", tool: .blur, editing: editing)
            shortcutButton("0", tool: .crop, editing: editing)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    func shortcutButton(_ key: Character, tool: AnnotationTool, editing: Bool) -> some View {
        Button("") { selectedTool = tool }
            .keyboardShortcut(KeyEquivalent(key), modifiers: [])
            .disabled(editing)
    }
}
