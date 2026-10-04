import SwiftUI

/// Filename + Copy/Share header bar. See `EditorView.swift`'s header for how this file relates
/// to the rest of the type.
extension EditorView {
    var headerBar: some View {
        HStack(spacing: 10) {
            filename
            Spacer()
            if showSavedConfirmation {
                Label("Saved", systemImage: "checkmark.circle.fill")
                    .foregroundColor(EditorColors.success)
                    .font(.system(size: 12, weight: .semibold))
                    .transition(.opacity)
            }
            Button { onRevealInFinder(currentURL) } label: {
                Label("Reveal", systemImage: "folder")
            }
            .help("Show this capture in the Finder")
            Button { onSaveAs(annotations) } label: {
                Label("Save As…", systemImage: "square.and.arrow.down")
            }
            // Not plain ⌘S: there's no document to "save" — auto-save already handles that — so
            // this is explicitly an export-a-copy action.
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .help("Export a copy as PNG or JPEG (⇧⌘S)")
            Menu {
                Toggle("Border", isOn: copyStyleBinding(\.border))
                Toggle("Drop Shadow", isOn: copyStyleBinding(\.shadow))
            } label: {
                Image(systemName: "square.dashed")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("What Copy adds around the image: a border, a drop shadow")
            Button { onCopy(annotations) } label: {
                Label("Copy", systemImage: "square.on.square")
            }
            // ⇧⌘C, not ⌘C: plain ⌘C belongs to the Edit menu so it still copies text from a text
            // field or the rename box.
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .help("Copy the annotated image to the clipboard (⇧⌘C)")
            Button { onShare(annotations) } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .help("Share the annotated image")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(EditorColors.s1)
        .foregroundColor(EditorColors.t1)
    }

    private func copyStyleBinding(_ keyPath: WritableKeyPath<CopyStyle, Bool>) -> Binding<Bool> {
        Binding(
            get: { copyStyle[keyPath: keyPath] },
            set: { copyStyle[keyPath: keyPath] = $0; onCopyStyleChanged(copyStyle) }
        )
    }

    /// Click-to-rename, Finder-style: the name is plain text until clicked, then an inline field.
    /// Return commits, Escape reverts, and clicking away commits (which is what Finder does, and
    /// what makes an accidental click-away not feel like lost typing).
    @ViewBuilder
    private var filename: some View {
        if isRenaming {
            TextField("Name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(EditorColors.t1)
                .focused($renameFieldFocused)
                .frame(maxWidth: 380)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(EditorColors.s0))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(EditorColors.accent, lineWidth: 1))
                .onSubmit { commitRename() }
                .onExitCommand { isRenaming = false }
                .onChange(of: renameFieldFocused) { _, focused in
                    // `onExitCommand` clears `isRenaming` before focus drops, so an Escape lands
                    // here with nothing left to commit — only a genuine click-away still commits.
                    if !focused, isRenaming { commitRename() }
                }
        } else {
            Text(currentURL.lastPathComponent)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(EditorColors.t1)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture { if onRename != nil { beginRename() } }
                .help(onRename != nil ? "Click to rename this capture" : "")
        }
    }

    /// Seeds the field with the name minus its extension — the extension is managed for the user
    /// (and re-applied on save), so putting it in the field only invites it being typed away.
    func beginRename() {
        guard onRename != nil else { return }
        draftName = currentURL.deletingPathExtension().lastPathComponent
        isRenaming = true
        renameFieldFocused = true
    }

    func commitRename() {
        isRenaming = false
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentURL.deletingPathExtension().lastPathComponent else { return }
        onRename?(currentURL, trimmed, annotations)
    }
}
