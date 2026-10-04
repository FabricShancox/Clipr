import SwiftUI

/// The live text-editing overlay. See `AnnotationCanvasView.swift`'s header for how this file
/// relates to the rest of the type.
extension AnnotationCanvasView {
    /// While `editingTextID` is set, a real `TextEditor` sits directly over that annotation's
    /// frame so the user can type. Bound straight through to the stored `.text` payload (via
    /// `editingTextBinding`) rather than a separate local buffer, so every keystroke is already
    /// "saved" into `annotations` — closing the editor (Escape, or starting any other gesture)
    /// never needs a separate commit step.
    ///
    /// A `TextEditor`, not a `TextField`: a `TextField` always treats Return as "submit and end
    /// editing," with no way to type a literal newline into it. `TextEditor` inserts a newline on
    /// Return instead, so multi-line text annotations are actually possible; Escape
    /// (`.onExitCommand`) is the explicit way to finish editing now that Return no longer doubles
    /// as that.
    @ViewBuilder
    var textEditingOverlay: some View {
        if let id = editingTextID, let annotation = annotations.first(where: { $0.id == id }),
           case .text(_, let style) = annotation.kind {
            let frame = swiftUIFrame(fromRendererFrame: annotation.frame, canvasHeight: canvasHeight)
            let pad = Self.textEditorLinePadding
            // The box grows to fit as the user types (see `editingTextBinding`), and the text
            // wraps at exactly `frame.width` — the same width the static text and the renderer
            // wrap at, so nothing re-flows when editing ends. NSTextView keeps a line-fragment
            // padding on each side of its text, so the editor is widened by that much and shifted
            // left to line its glyphs up with the frame.
            TextEditor(text: editingTextBinding)
                .font(styledSwiftUIFont(style))
                .foregroundColor(displayColor(for: annotation))
                .multilineTextAlignment(swiftUITextAlignment(style.horizontalAlign))
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .background(Color.clear)
                .frame(width: frame.width + pad * 2, height: frame.height)
                .background(
                    style.border
                        ? RoundedRectangle(cornerRadius: 4)
                            .stroke(displayColor(for: annotation), lineWidth: 1.5)
                            .padding(.horizontal, pad - textBorderInset.width)
                            .padding(.vertical, -textBorderInset.height)
                        : nil
                )
                .position(x: frame.midX, y: frame.midY)
                .focused($textFieldFocused)
                .onExitCommand { finishTextEditing() }
                .onAppear { textFieldFocused = true }
        }
    }

    /// Ends the current text edit, discarding the annotation if nothing was typed.
    ///
    /// `commitText` creates the annotation up front so the editor has something to bind to, so
    /// abandoning a text box — click the canvas with the Text tool, then press Escape — used to
    /// leave a permanent invisible one behind. It still hit-tests (with `contains`'s 10pt
    /// tolerance on top), so later clicks in that area selected the invisible box instead of
    /// drawing, and it was written to the sidecar and restored on every reopen.
    func finishTextEditing() {
        defer { editingTextID = nil }
        guard let id = editingTextID,
              let annotation = annotations.first(where: { $0.id == id }),
              case .text(let string, _) = annotation.kind,
              string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        annotations.removeAll { $0.id == id }
        selectedIDs.remove(id)
    }

    func displayColor(for annotation: AnnotationObject) -> Color {
        Color(
            red: Double(annotation.color.red), green: Double(annotation.color.green),
            blue: Double(annotation.color.blue), opacity: Double(annotation.color.alpha)
        )
    }

    var editingTextBinding: Binding<String> {
        Binding(
            get: {
                guard let id = editingTextID, let annotation = annotations.first(where: { $0.id == id }),
                      case .text(let string, _) = annotation.kind else { return "" }
                return string
            },
            set: { newValue in
                guard let id = editingTextID, let index = annotations.firstIndex(where: { $0.id == id }),
                      case .text(_, let style) = annotations[index].kind else { return }
                var updated = annotations[index]
                updated.kind = .text(newValue, style)
                // Grow the box to fit, so text longer than it is wrapped and shown in full rather
                // than truncated on the canvas and clipped in the export.
                annotations[index] = updated.fittedToText()
            }
        )
    }

    /// `NSTextView`'s default `lineFragmentPadding`, which SwiftUI's `TextEditor` keeps on each
    /// side of its text.
    static let textEditorLinePadding: CGFloat = 5
}
