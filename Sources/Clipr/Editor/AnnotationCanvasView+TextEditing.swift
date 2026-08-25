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
            TextEditor(text: editingTextBinding)
                .font(styledSwiftUIFont(style))
                .foregroundColor(displayColor(for: annotation))
                .multilineTextAlignment(swiftUITextAlignment(style.horizontalAlign))
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .frame(width: max(frame.width, 80), height: max(frame.height, 32))
                .padding(style.border ? 4 : 0)
                .background(
                    style.border
                        ? RoundedRectangle(cornerRadius: 4).stroke(displayColor(for: annotation), lineWidth: 1.5)
                        : nil
                )
                .position(x: max(frame.width, 80) / 2 + frame.minX, y: frame.midY)
                .focused($textFieldFocused)
                .onExitCommand { editingTextID = nil }
                .onAppear { textFieldFocused = true }
        }
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
                annotations[index].kind = .text(newValue, style)
            }
        )
    }
}
