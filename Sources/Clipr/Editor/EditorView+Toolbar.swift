import SwiftUI

/// The tool/color/stroke toolbar and its button styles. See `EditorView.swift`'s header for how
/// this file relates to the rest of the type.
extension EditorView {
    var toolbar: some View {
        HStack(spacing: 10) {
            historyButtons

            Divider().frame(height: 20)

            toolPicker

            Divider().frame(height: 20)

            HStack(spacing: 5) {
                ForEach(Array(EditorView.swatchColors.enumerated()), id: \.offset) { _, swatch in
                    colorSwatch(swatch, binding: colorBinding)
                }
            }

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                strokeButton(width: 2, dotSize: 5, label: "Thin", binding: strokeWidthBinding)
                strokeButton(width: 4, dotSize: 8, label: "Medium", binding: strokeWidthBinding)
                strokeButton(width: 8, dotSize: 12, label: "Thick", binding: strokeWidthBinding)
            }

            // Shown while actively placing new text, OR while an already-placed text
            // annotation is selected — in the latter case these controls edit THAT
            // annotation's style directly instead of the "next new text" default.
            if selectedTool == .text || selectedTextAnnotation != nil {
                Divider().frame(height: 20)
                textStyleControls(binding: textStyleBinding)
            }

            Spacer()

            zoomControl
        }
        .padding(10)
        .background(EditorColors.s2)
    }

    /// Undo, redo and delete.
    private var historyButtons: some View {
        HStack(spacing: 2) {
            // All three are `.disabled` while a text field is active, which also disables their
            // keyboard shortcuts — otherwise Backspace deletes the selected annotation instead
            // of a character, and ⌘Z undoes an annotation instead of the typing.
            Button { undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 30, height: 30).contentShape(Rectangle()) }
                .disabled(history.undo.isEmpty || isTextEntryActive)
                .keyboardShortcut("z", modifiers: .command)
                .help("Undo")
                .accessibilityLabel("Undo")
            Button { redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 30, height: 30).contentShape(Rectangle()) }
                .disabled(history.redo.isEmpty || isTextEntryActive)
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .help("Redo")
                .accessibilityLabel("Redo")
            Button { deleteSelected() } label: { Image(systemName: "trash").frame(width: 30, height: 30).contentShape(Rectangle()) }
                .disabled(selectedIDs.isEmpty || isTextEntryActive)
                .keyboardShortcut(.delete, modifiers: [])
                .help("Delete selected annotations")
                .accessibilityLabel("Delete selected annotations")
        }
        .buttonStyle(.plain)
        .foregroundColor(EditorColors.t1)
    }

    /// The drawing tools.
    private var toolPicker: some View {
        HStack(spacing: 2) {
            toolButton(.select, systemImage: "cursorarrow", help: "Select (1)")
            toolButton(.rectangle, systemImage: "rectangle", help: "Box (2)")
            toolButton(.ellipse, systemImage: "circle", help: "Ellipse (3)")
            toolButton(.arrow, systemImage: "arrow.up.right", help: "Arrow (4)")
            toolButton(.freehand, systemImage: "scribble", help: "Pen (5)")
            toolButton(.text, systemImage: "textformat", help: "Text (6)")
            stampToolButton
            toolButton(.highlighter, systemImage: "highlighter", help: "Highlight (8)")
            redactToolButton
            toolButton(.crop, systemImage: "crop", help: "Crop (0)")
        }
        .padding(4)
        .background(EditorColors.s1)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(EditorColors.line, lineWidth: 1))
    }

    func toolButton(_ tool: AnnotationTool, systemImage: String, help: String) -> some View {
        let active = selectedTool == tool
        return Button { selectedTool = tool } label: {
            Image(systemName: systemImage)
                .frame(width: 30, height: 30)
                .foregroundColor(active ? EditorColors.accent : EditorColors.t2)
                .background(active ? EditorColors.accent12 : Color.clear)
                .cornerRadius(8)
                // A `Button`'s default clickable region on macOS follows an `Image` label's own
                // rendered glyph shape, not a `.frame()`/`.background()` wrapped around it —
                // `.contentShape` has to be applied INSIDE the label, to the exact view that
                // frame belongs to, or the button itself still infers its hit area from the
                // glyph alone and clicking the empty padding around the icon does nothing.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    func colorSwatch(_ swatch: RGBAColor, binding: Binding<RGBAColor>) -> some View {
        let active = binding.wrappedValue == swatch
        return Button { binding.wrappedValue = swatch } label: {
            Circle()
                .fill(Color(red: swatch.red, green: swatch.green, blue: swatch.blue, opacity: swatch.alpha))
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(active ? EditorColors.accent : EditorColors.line, lineWidth: active ? 2 : 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.swatchName(swatch))
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    static func swatchName(_ swatch: RGBAColor) -> String {
        let names = ["White", "Grey", "Blue", "Purple", "Orange", "Red"]
        return swatchColors.firstIndex(of: swatch).map { names[$0] + " colour" } ?? "Colour"
    }

    /// Each preset is a full, clearly-labeled hit target (not just a tiny dot) — the dot is
    /// still shown so the relative weight is visible at a glance, but the clickable area and a
    /// text label make the three sizes easy to tell apart and easy to actually hit.
    func strokeButton(width: CGFloat, dotSize: CGFloat, label: String, binding: Binding<CGFloat>) -> some View {
        let active = binding.wrappedValue == width
        return Button { binding.wrappedValue = width } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(active ? EditorColors.accent : EditorColors.t2)
                    .frame(width: dotSize, height: dotSize)
                Text(label)
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .foregroundColor(active ? EditorColors.accent : EditorColors.t2)
            .background(active ? EditorColors.accent12 : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
