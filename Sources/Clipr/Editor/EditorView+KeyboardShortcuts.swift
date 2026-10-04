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
            // Whichever stamp the toolbar slot is currently showing, not always the numbered one.
            shortcutButton("7", tool: currentStampTool, editing: editing)
            shortcutButton("8", tool: .highlighter, editing: editing)
            shortcutButton("9", tool: .blur, editing: editing)
            shortcutButton("0", tool: .crop, editing: editing)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        // Invisible keyboard-shortcut carriers; opacity alone leaves them in VoiceOver as
        // unlabeled buttons.
        .accessibilityHidden(true)
    }

    /// Esc and Return finish with the capture: Esc closes the window, leaving whatever is on the
    /// clipboard (the raw capture, or an earlier Copy); Return copies the annotated image and then
    /// closes. Esc with an annotation selected clears the selection first, so it keeps its usual
    /// "back out" meaning before it dismisses. Disabled during text entry, where Esc ends editing
    /// and Return types a newline.
    var dismissShortcuts: some View {
        let editing = isTextEntryActive
        return Group {
            Button("") {
                if !selectedIDs.isEmpty {
                    selectedIDs = []
                } else {
                    onClose()
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(editing)
            Button("") {
                // With one text annotation selected, Return goes back into it to edit — the
                // keyboard counterpart of double-clicking it.
                if let text = selectedTextAnnotation {
                    editingTextID = text.id
                    return
                }
                onCopy(annotations)
                onClose()
            }
            .keyboardShortcut(.return, modifiers: [])
            .disabled(editing)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        // Invisible keyboard-shortcut carriers; opacity alone leaves them in VoiceOver as
        // unlabeled buttons.
        .accessibilityHidden(true)
    }

    func shortcutButton(_ key: Character, tool: AnnotationTool, editing: Bool) -> some View {
        Button("") { selectedTool = tool }
            .keyboardShortcut(KeyEquivalent(key), modifiers: [])
            .disabled(editing)
    }
}
