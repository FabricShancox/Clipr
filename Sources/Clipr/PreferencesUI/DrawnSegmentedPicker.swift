import SwiftUI

/// A segmented control drawn in SwiftUI, for use inside a grouped `Form`.
///
/// Not a native `.segmented` `Picker`: a grouped `Form` is List-backed on macOS, and the native
/// control sets accessibility attributes while its row is being updated. That re-enters the row's
/// update and can leave SwiftUI in an attribute cycle it never exits — the same ingredients that
/// froze Review (see `ReviewRow.sizePicker`). Here the control's `.disabled` also flips whenever
/// the toggle above it changes, which is exactly such an update.
struct DrawnSegmentedPicker<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    let selected = option.value == selection
                    Button { selection = option.value } label: {
                        Text(option.title)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .frame(minWidth: 52, minHeight: 20)
                            .padding(.horizontal, 4)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Color.accentColor : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.15)))
            .opacity(isEnabled ? 1 : 0.45)
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
        }
    }
}
