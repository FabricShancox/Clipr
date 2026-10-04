import SwiftUI

/// Font/alignment controls for text annotations. See `EditorView.swift`'s header for how this
/// file relates to the rest of the type.
extension EditorView {
    /// The binding the text-style controls actually edit: the selected text annotation's own
    /// style when one is selected, otherwise `currentTextStyle` (the default applied to the
    /// next text annotation placed). Looks the selected annotation up by id inside the
    /// closures (rather than capturing an index) so it stays correct even if `annotations`
    /// is mutated elsewhere between a get and a set.
    var textStyleBinding: Binding<TextStyle> {
        guard let selected = selectedTextAnnotation else { return $currentTextStyle }
        return Binding(
            get: {
                guard let annotation = annotations.first(where: { $0.id == selected.id }),
                      case .text(_, let style) = annotation.kind else { return selected.style }
                return style
            },
            set: { newStyle in
                mutateAnnotations { list in
                    guard let index = list.firstIndex(where: { $0.id == selected.id }),
                          case .text(let string, _) = list[index].kind else { return }
                    list[index].kind = .text(string, newStyle)
                    // A bigger or bold font needs more room; keep the whole text visible.
                    list[index] = list[index].fittedToText()
                }
            }
        )
    }

    /// Font size / bold / italic / border / alignment. Only shown while the Text tool is active
    /// or a text annotation is selected — these don't apply to any other tool.
    func textStyleControls(binding: Binding<TextStyle>) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Button {
                    binding.wrappedValue.fontSize = max(8, binding.wrappedValue.fontSize - 2)
                } label: { Image(systemName: "minus").frame(width: 22, height: 22).contentShape(Rectangle()) }
                Text("\(Int(binding.wrappedValue.fontSize))")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22)
                    .foregroundColor(EditorColors.t1)
                Button {
                    binding.wrappedValue.fontSize = min(96, binding.wrappedValue.fontSize + 2)
                } label: { Image(systemName: "plus").frame(width: 22, height: 22).contentShape(Rectangle()) }
            }
            .buttonStyle(.plain)
            .foregroundColor(EditorColors.t1)

            textStyleToggle(isOn: Binding(get: { binding.wrappedValue.bold }, set: { binding.wrappedValue.bold = $0 }), systemImage: "bold", help: "Bold")
            textStyleToggle(isOn: Binding(get: { binding.wrappedValue.italic }, set: { binding.wrappedValue.italic = $0 }), systemImage: "italic", help: "Italic")
            textStyleToggle(isOn: Binding(get: { binding.wrappedValue.border }, set: { binding.wrappedValue.border = $0 }), systemImage: "rectangle", help: "Border")

            HStack(spacing: 2) {
                alignButton(.left, current: binding.wrappedValue.horizontalAlign, systemImage: "text.alignleft", help: "Align left") { binding.wrappedValue.horizontalAlign = $0 }
                alignButton(.center, current: binding.wrappedValue.horizontalAlign, systemImage: "text.aligncenter", help: "Align center") { binding.wrappedValue.horizontalAlign = $0 }
                alignButton(.right, current: binding.wrappedValue.horizontalAlign, systemImage: "text.alignright", help: "Align right") { binding.wrappedValue.horizontalAlign = $0 }
            }
            HStack(spacing: 2) {
                alignButton(.top, current: binding.wrappedValue.verticalAlign, systemImage: "align.vertical.top", help: "Align top") { binding.wrappedValue.verticalAlign = $0 }
                alignButton(.middle, current: binding.wrappedValue.verticalAlign, systemImage: "align.vertical.center", help: "Align middle") { binding.wrappedValue.verticalAlign = $0 }
                alignButton(.bottom, current: binding.wrappedValue.verticalAlign, systemImage: "align.vertical.bottom", help: "Align bottom") { binding.wrappedValue.verticalAlign = $0 }
            }
        }
    }

    func alignButton<T: Equatable>(_ value: T, current: T, systemImage: String, help: String, set: @escaping (T) -> Void) -> some View {
        let active = current == value
        return Button { set(value) } label: {
            Image(systemName: systemImage)
                .frame(width: 22, height: 22)
                .foregroundColor(active ? EditorColors.accent : EditorColors.t2)
                .background(active ? EditorColors.accent12 : Color.clear)
                .cornerRadius(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    func textStyleToggle(isOn: Binding<Bool>, systemImage: String, help: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Image(systemName: systemImage)
                .frame(width: 26, height: 26)
                .foregroundColor(isOn.wrappedValue ? EditorColors.accent : EditorColors.t2)
                .background(isOn.wrappedValue ? EditorColors.accent12 : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
