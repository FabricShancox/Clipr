import SwiftUI

/// `AnnotationTool` (Task 13, `AnnotationCanvasView.swift`) only declares `Equatable`, but
/// SwiftUI's `Picker`/selection state used below requires `Hashable`. Adding the conformance here
/// (rather than editing that file) keeps this file's changes scoped to what it owns. Synthesis of
/// `hash(into:)` for an enum with an associated value only happens automatically when the
/// conformance is declared in the same file as the type, so it's implemented by hand here;
/// `StampKind`'s case-only, `String`-raw-value enum already gets `Hashable` for free from the
/// compiler, so `hasher.combine(kind)` below is valid.
extension AnnotationTool: Hashable {
    func hash(into hasher: inout Hasher) {
        switch self {
        case .select: hasher.combine(0)
        case .rectangle: hasher.combine(1)
        case .ellipse: hasher.combine(2)
        case .arrow: hasher.combine(3)
        case .freehand: hasher.combine(4)
        case .text: hasher.combine(5)
        case .highlighter: hasher.combine(6)
        case .blur: hasher.combine(7)
        case .crop: hasher.combine(9)
        case .stamp(let kind):
            hasher.combine(8)
            hasher.combine(kind)
        }
    }
}

/// Dark palette lifted from the "Screenshot Editor Redesign" Claude Design project
/// (Origin Studio color tokens, dark theme) — kept as plain `Color` constants rather than an
/// asset catalog since this editor doesn't otherwise need one.
private enum EditorColors {
    static let s0 = Color(red: 0x14 / 255.0, green: 0x1A / 255.0, blue: 0x21 / 255.0)
    static let s1 = Color(red: 0x1C / 255.0, green: 0x25 / 255.0, blue: 0x2E / 255.0)
    static let s2 = Color(red: 0x28 / 255.0, green: 0x32 / 255.0, blue: 0x3D / 255.0)
    static let t1 = Color.white
    static let t2 = Color(red: 0x91 / 255.0, green: 0x9E / 255.0, blue: 0xAB / 255.0)
    static let line = Color(red: 145 / 255.0, green: 158 / 255.0, blue: 171 / 255.0).opacity(0.16)
    static let accent = Color(red: 0x33 / 255.0, green: 0x99 / 255.0, blue: 0xFF / 255.0)
    static let accent12 = Color(red: 0x33 / 255.0, green: 0x99 / 255.0, blue: 0xFF / 255.0).opacity(0.12)
    static let success = Color(red: 0x4C / 255.0, green: 0xAF / 255.0, blue: 0x50 / 255.0)
}

struct EditorView: View {
    let image: NSImage
    let currentURL: URL
    let recentCaptures: [URL]

    @State var annotations: [AnnotationObject] = []
    @State private var selectedTool: AnnotationTool = .select
    @State private var currentColor = EditorView.swatchColors[2] // accent blue, matches the design's default
    @State private var currentStrokeWidth: CGFloat = 4
    @State private var currentTextStyle = TextStyle.default
    @State private var undoStack: [[AnnotationObject]] = []
    @State private var redoStack: [[AnnotationObject]] = []
    @State private var zoomPercent: Double = 100
    @State private var viewportSize: CGSize = .zero
    @State private var hasAutoFit = false
    @State private var nextStampNumber = 1
    @State private var showSavedConfirmation = false
    /// Debounces auto-save so every single keystroke/drag doesn't hit disk — only the trailing
    /// edit in a burst does. Cancelling and replacing this on every `annotations` change is what
    /// gives the debounce its "wait for a pause" behavior.
    @State private var autoSaveTask: Task<Void, Never>?

    /// Switching to a different Recent capture used to discard whatever was mid-edit, since the
    /// old flow only ever wrote to disk on an explicit Save click. Auto-save (`onAutoSave`, fired
    /// on every settled edit — see `scheduleAutoSave`) means there's no manual Save button
    /// anymore: by the time the user switches images, the edit is already on disk.
    let onOpenCapture: (URL) -> Void
    let onAutoSave: ([AnnotationObject]) -> Void
    let onCopy: ([AnnotationObject]) -> Void
    let onShare: ([AnnotationObject]) -> Void
    /// Crop rect in renderer space (the same y-up-from-bottom space `AnnotationObject.frame`
    /// uses) — `EditorWindowController` owns the base `NSImage` and does the actual pixel crop,
    /// since this view only has a `let image`, not a mutable one.
    let onCropApplied: (CGRect) -> Void

    private static let swatchColors: [RGBAColor] = [
        RGBAColor(red: 1, green: 1, blue: 1, alpha: 1),
        RGBAColor(red: 0x91 / 255.0, green: 0x9E / 255.0, blue: 0xAB / 255.0, alpha: 1),
        RGBAColor(red: 0x33 / 255.0, green: 0x99 / 255.0, blue: 0xFF / 255.0, alpha: 1),
        RGBAColor(red: 0x8E / 255.0, green: 0x33 / 255.0, blue: 0xFF / 255.0, alpha: 1),
        RGBAColor(red: 1.0, green: 0xB7 / 255.0, blue: 0x4D / 255.0, alpha: 1),
        RGBAColor(red: 0xF4 / 255.0, green: 0x43 / 255.0, blue: 0x36 / 255.0, alpha: 1),
    ]

    private var numberTool: AnnotationTool { .stamp(stampKind(for: nextStampNumber)) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                headerBar
                toolbar
                canvasArea
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(EditorColors.s0)
    }

    // MARK: - Sidebar (Recent captures)

    private var sidebar: some View {
        VStack(spacing: 12) {
            Text("RECENT")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.1)
                .foregroundColor(EditorColors.t2)
                .padding(.top, 16)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(recentCaptures, id: \.self) { url in
                        Button { onOpenCapture(url) } label: {
                            VStack(spacing: 6) {
                                thumbnail(for: url)
                                    .frame(width: 56, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(relativeLabel(for: url))
                                    .font(.system(size: 10))
                                    .foregroundColor(EditorColors.t2)
                                    .lineLimit(1)
                            }
                            .padding(6)
                            .background(url == currentURL ? EditorColors.accent12 : Color.clear)
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .help(url.lastPathComponent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(width: 96)
        .background(EditorColors.s2)
    }

    private func thumbnail(for url: URL) -> some View {
        Group {
            if let img = NSImage(contentsOf: url) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(EditorColors.s1)
            }
        }
    }

    private func relativeLabel(for url: URL) -> String {
        guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            return url.lastPathComponent
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Header (filename + Copy/Save/Share)

    private var headerBar: some View {
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

    /// Cancels any pending auto-save and schedules a new one ~800ms out. Called from
    /// `.onChange(of: annotations)`, so a burst of edits (typing, a multi-point freehand drag)
    /// collapses into a single write once things settle, instead of hitting disk on every
    /// intermediate state.
    private func scheduleAutoSave() {
        autoSaveTask?.cancel()
        let snapshot = annotations
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            onAutoSave(snapshot)
            withAnimation { showSavedConfirmation = true }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showSavedConfirmation = false }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(undoStack.isEmpty)
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Undo")
                Button { redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(redoStack.isEmpty)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .help("Redo")
            }
            .buttonStyle(.plain)
            .foregroundColor(EditorColors.t1)

            Divider().frame(height: 20)

            HStack(spacing: 2) {
                toolButton(.select, systemImage: "cursorarrow", help: "Select")
                toolButton(.rectangle, systemImage: "rectangle", help: "Box")
                toolButton(.ellipse, systemImage: "circle", help: "Ellipse")
                toolButton(.arrow, systemImage: "arrow.up.right", help: "Arrow")
                toolButton(.freehand, systemImage: "scribble", help: "Pen")
                toolButton(.text, systemImage: "textformat", help: "Text")
                toolButton(numberTool, systemImage: "\(nextStampNumber).circle.fill", help: "Numbered step (auto-increments)")
                toolButton(.highlighter, systemImage: "highlighter", help: "Highlight")
                toolButton(.blur, systemImage: "checkerboard.rectangle", help: "Blur / redact")
                toolButton(.crop, systemImage: "crop", help: "Crop")
            }
            .padding(4)
            .background(EditorColors.s1)
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(EditorColors.line, lineWidth: 1))

            Divider().frame(height: 20)

            HStack(spacing: 5) {
                ForEach(Array(EditorView.swatchColors.enumerated()), id: \.offset) { _, swatch in
                    colorSwatch(swatch)
                }
            }

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                strokeButton(width: 2, dotSize: 5, label: "Thin")
                strokeButton(width: 4, dotSize: 8, label: "Medium")
                strokeButton(width: 8, dotSize: 12, label: "Thick")
            }

            if selectedTool == .text {
                Divider().frame(height: 20)
                textStyleControls
            }

            Spacer()

            zoomControl
        }
        .padding(10)
        .background(EditorColors.s2)
    }

    /// Only shown while the Text tool is active — font size / bold / italic don't apply to any
    /// other tool. Changing these only affects text placed AFTER the change, matching how
    /// `currentColor`/`currentStrokeWidth` already work for every other tool (not retroactive
    /// on already-placed annotations).
    private var textStyleControls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Button {
                    currentTextStyle.fontSize = max(8, currentTextStyle.fontSize - 2)
                } label: { Image(systemName: "minus") }
                Text("\(Int(currentTextStyle.fontSize))")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22)
                    .foregroundColor(EditorColors.t1)
                Button {
                    currentTextStyle.fontSize = min(96, currentTextStyle.fontSize + 2)
                } label: { Image(systemName: "plus") }
            }
            .buttonStyle(.plain)
            .foregroundColor(EditorColors.t1)

            textStyleToggle(isOn: $currentTextStyle.bold, systemImage: "bold", help: "Bold")
            textStyleToggle(isOn: $currentTextStyle.italic, systemImage: "italic", help: "Italic")
        }
    }

    private func textStyleToggle(isOn: Binding<Bool>, systemImage: String, help: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Image(systemName: systemImage)
                .frame(width: 26, height: 26)
                .foregroundColor(isOn.wrappedValue ? EditorColors.accent : EditorColors.t2)
                .background(isOn.wrappedValue ? EditorColors.accent12 : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func toolButton(_ tool: AnnotationTool, systemImage: String, help: String) -> some View {
        let active = selectedTool == tool
        return Button { selectedTool = tool } label: {
            Image(systemName: systemImage)
                .frame(width: 30, height: 30)
                .foregroundColor(active ? EditorColors.accent : EditorColors.t2)
                .background(active ? EditorColors.accent12 : Color.clear)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func colorSwatch(_ swatch: RGBAColor) -> some View {
        let active = currentColor == swatch
        return Button { currentColor = swatch } label: {
            Circle()
                .fill(Color(red: swatch.red, green: swatch.green, blue: swatch.blue, opacity: swatch.alpha))
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(active ? EditorColors.accent : EditorColors.line, lineWidth: active ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    /// Each preset is a full, clearly-labeled hit target (not just a tiny dot) — the dot is
    /// still shown so the relative weight is visible at a glance, but the clickable area and a
    /// text label make the three sizes easy to tell apart and easy to actually hit.
    private func strokeButton(width: CGFloat, dotSize: CGFloat, label: String) -> some View {
        let active = currentStrokeWidth == width
        return Button { currentStrokeWidth = width } label: {
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
        }
        .buttonStyle(.plain)
    }

    private func stampKind(for number: Int) -> StampKind {
        switch number {
        case 1: return .number1
        case 2: return .number2
        case 3: return .number3
        case 4: return .number4
        case 5: return .number5
        case 6: return .number6
        case 7: return .number7
        case 8: return .number8
        default: return .number9
        }
    }

    /// Called synchronously the instant a new annotation commits — see
    /// `AnnotationCanvasView.onAnnotationCommitted`. Auto-advancing here, right at the moment of
    /// placement, rather than inferring it later from an `annotations.count` change, is what
    /// makes the numbered-stamp counter reliably advance 1 -> 2 -> 3... on every placement.
    private func handleAnnotationCommitted(_ annotation: AnnotationObject) {
        guard case .stamp(let kind) = annotation.kind, kind.rawValue.hasPrefix("number") else { return }
        nextStampNumber = min(nextStampNumber + 1, 9)
        selectedTool = .stamp(stampKind(for: nextStampNumber))
    }

    // MARK: - Zoom + scrollable canvas

    private var zoomControl: some View {
        HStack(spacing: 2) {
            Button { zoomPercent = max(10, zoomPercent - 10) } label: { Image(systemName: "minus") }
                .help("Zoom out")
            Text("\(Int(zoomPercent))%")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 40)
                .foregroundColor(EditorColors.t1)
            Button { zoomPercent = min(400, zoomPercent + 10) } label: { Image(systemName: "plus") }
                .help("Zoom in")
            Button("Fit") { zoomToFit() }
                .foregroundColor(EditorColors.accent)
                .help("Fit the whole capture in the window")
        }
        .buttonStyle(.plain)
        .foregroundColor(EditorColors.t1)
        .padding(6)
        .background(EditorColors.s1)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(EditorColors.line, lineWidth: 1))
    }

    private var canvasArea: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                AnnotationCanvasView(
                    image: image,
                    annotations: annotationsBinding,
                    selectedTool: $selectedTool,
                    currentColor: $currentColor,
                    currentStrokeWidth: $currentStrokeWidth,
                    currentTextStyle: $currentTextStyle,
                    onAnnotationCommitted: handleAnnotationCommitted,
                    onCropRequested: onCropApplied
                )
                .scaleEffect(zoomPercent / 100, anchor: .topLeading)
                .frame(width: image.size.width * zoomPercent / 100, height: image.size.height * zoomPercent / 100)
                .padding(24)
            }
            .background(EditorColors.s0)
            .onAppear {
                viewportSize = geo.size
                if !hasAutoFit {
                    zoomToFit()
                    hasAutoFit = true
                }
            }
            .onChange(of: geo.size) { _, newSize in
                viewportSize = newSize
            }
        }
        .onChange(of: annotations) { _, _ in
            scheduleAutoSave()
        }
    }

    /// Scales so the full image fits the visible scroll viewport, never upscaling past 100% —
    /// this is the fix for "the capture is too zoomed in to see all of it": rather than always
    /// opening at a fixed 1:1 size, a capture larger than the window now starts scaled down to
    /// fit, and the user can zoom back in or drag-scroll as needed.
    private func zoomToFit() {
        guard viewportSize.width > 0, viewportSize.height > 0, image.size.width > 0, image.size.height > 0 else { return }
        let scaleX = (viewportSize.width - 48) / image.size.width
        let scaleY = (viewportSize.height - 48) / image.size.height
        let fitScale = max(min(scaleX, scaleY), 0.05)
        zoomPercent = (min(fitScale, 1.0) * 100).rounded()
    }

    private var annotationsBinding: Binding<[AnnotationObject]> {
        Binding(
            get: { annotations },
            set: { newValue in
                undoStack.append(annotations)
                redoStack.removeAll()
                annotations = newValue
            }
        )
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
