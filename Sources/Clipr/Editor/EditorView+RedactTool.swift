import SwiftUI

/// The toolbar's redact slot and its popover of redaction styles.
extension EditorView {
    /// The redact slot, following the same pattern as the stamp slot: click to use it, long press
    /// or the corner marker to choose how it hides things.
    var redactToolButton: some View {
        let active = selectedTool == .blur
        return Button { selectedTool = .blur } label: {
            Image(systemName: redactionStyle == .solid ? "rectangle.fill" : "checkerboard.rectangle")
                .frame(width: 30, height: 30)
                .foregroundColor(active ? EditorColors.accent : EditorColors.t2)
                .background(active ? EditorColors.accent12 : Color.clear)
                .cornerRadius(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            Button { showingRedactionStyles = true } label: {
                StampAlternativesIndicator()
                    .fill(active ? EditorColors.accent : EditorColors.t2)
                    .frame(width: 5, height: 5)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3).onEnded { _ in showingRedactionStyles = true }
        )
        .popover(isPresented: $showingRedactionStyles, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                redactionStyleOption(.pixelate, symbol: "checkerboard.rectangle", title: "Pixelate")
                redactionStyleOption(.solid, symbol: "rectangle.fill", title: "Solid block")
            }
            .padding(6)
            .frame(width: 232)
        }
        .help("Redact — click to use, hold or click the corner to choose pixelate or solid (9)")
        .accessibilityLabel("Redact (9)")
    }

    private func redactionStyleOption(_ style: RedactionStyle, symbol: String, title: String) -> some View {
        let isCurrent = redactionStyle == style
        return Button {
            redactionStyle = style
            selectedTool = .blur
            showingRedactionStyles = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18)
                Text(title)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
