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
            Button { onCopy(annotations) } label: {
                Label("Copy", systemImage: "square.on.square")
            }
            .help("Copy the annotated image to the clipboard")
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
                .onTapGesture { beginRename() }
                .help("Click to rename this capture")
        }
    }

    /// Seeds the field with the name minus its extension — the extension is managed for the user
    /// (and re-applied on save), so putting it in the field only invites it being typed away.
    func beginRename() {
        draftName = currentURL.deletingPathExtension().lastPathComponent
        isRenaming = true
        renameFieldFocused = true
    }

    func commitRename() {
        isRenaming = false
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentURL.deletingPathExtension().lastPathComponent else { return }
        onRename(currentURL, trimmed, annotations)
    }
}
