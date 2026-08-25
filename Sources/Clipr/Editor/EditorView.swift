import SwiftUI

/// `AnnotationTool` (Task 13, `AnnotationCanvasView.swift`) only declares `Equatable`, but
/// SwiftUI's `Picker` selection binding — used below for the tool picker — requires `Hashable`.
/// Adding the conformance here (rather than editing Task 13's file) keeps this task's diff
/// scoped to the files it owns. Synthesis of `hash(into:)` for an enum with an associated value
/// only happens automatically when the conformance is declared in the same file as the type, so
/// it's implemented by hand here; `StampKind`'s case-only, `String`-raw-value enum already gets
/// Hashable for free from the compiler, so `hasher.combine(kind)` below is valid.
extension AnnotationTool: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .select: hasher.combine(0)
        case .rectangle: hasher.combine(1)
        case .arrow: hasher.combine(2)
        case .freehand: hasher.combine(3)
        case .text: hasher.combine(4)
        case .highlighter: hasher.combine(5)
        case .blur: hasher.combine(6)
        case .stamp(let kind):
            hasher.combine(7)
            hasher.combine(kind)
        }
    }
}

struct EditorView: View {
    let image: NSImage
    @State var annotations: [AnnotationObject] = []
    @State private var selectedTool: AnnotationTool = .select
    @State private var currentColor = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
    @State private var currentStrokeWidth: CGFloat = 3
    @State private var undoStack: [[AnnotationObject]] = []
    @State private var redoStack: [[AnnotationObject]] = []

    let onDone: ([AnnotationObject]) -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            AnnotationCanvasView(
                image: image,
                annotations: Binding(
                    get: { annotations },
                    set: { newValue in
                        undoStack.append(annotations)
                        redoStack.removeAll()
                        annotations = newValue
                    }
                ),
                selectedTool: $selectedTool,
                currentColor: $currentColor,
                currentStrokeWidth: $currentStrokeWidth
            )
        }
        .frame(minWidth: 480, minHeight: 360)
    }

    private var toolbar: some View {
        HStack {
            Picker("Tool", selection: $selectedTool) {
                Text("Select").tag(AnnotationTool.select)
                Text("Box").tag(AnnotationTool.rectangle)
                Text("Arrow").tag(AnnotationTool.arrow)
                Text("Pen").tag(AnnotationTool.freehand)
                Text("Text").tag(AnnotationTool.text)
                Text("Highlight").tag(AnnotationTool.highlighter)
                Text("Blur").tag(AnnotationTool.blur)
                ForEach(StampKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue.capitalized).tag(AnnotationTool.stamp(kind))
                }
            }
            .pickerStyle(.menu)

            ColorPicker("Color", selection: Binding(
                get: { Color(red: currentColor.red, green: currentColor.green, blue: currentColor.blue, opacity: currentColor.alpha) },
                set: { newColor in
                    let resolved = newColor.resolve(in: .init())
                    currentColor = RGBAColor(red: CGFloat(resolved.red), green: CGFloat(resolved.green), blue: CGFloat(resolved.blue), alpha: CGFloat(resolved.opacity))
                }
            ))

            Slider(value: $currentStrokeWidth, in: 1...12) { Text("Width") }
                .frame(width: 100)

            Button("Undo") { undo() }.disabled(undoStack.isEmpty)
            Button("Redo") { redo() }.disabled(redoStack.isEmpty)

            Spacer()

            Button("Discard", role: .destructive) { onDiscard() }
            Button("Done") { onDone(annotations) }
                .buttonStyle(.borderedProminent)
        }
        .padding(8)
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }
}
