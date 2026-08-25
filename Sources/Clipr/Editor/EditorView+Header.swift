import SwiftUI

/// Filename + Copy/Share header bar. See `EditorView.swift`'s header for how this file relates
/// to the rest of the type.
extension EditorView {
    var headerBar: some View {
        HStack(spacing: 10) {
            Text(currentURL.lastPathComponent)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(EditorColors.t1)
                .lineLimit(1)
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
}
