import SwiftUI

/// The tool/color/stroke toolbar and its button styles. See `EditorView.swift`'s header for how
/// this file relates to the rest of the type.
extension EditorView {
    var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                // All three are `.disabled` while a text field is active, which also disables their
                // keyboard shortcuts — otherwise Backspace deletes the selected annotation instead
                // of a character, and ⌘Z undoes an annotation instead of the typing.
                Button { undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 30, height: 30).contentShape(Rectangle()) }
                    .disabled(history.undo.isEmpty || isTextEntryActive)
                    .keyboardShortcut("z", modifiers: .command)
                    .help("Undo")
                Button { redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 30, height: 30).contentShape(Rectangle()) }
                    .disabled(history.redo.isEmpty || isTextEntryActive)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .help("Redo")
                Button { deleteSelected() } label: { Image(systemName: "trash").frame(width: 30, height: 30).contentShape(Rectangle()) }
                    .disabled(selectedIDs.isEmpty || isTextEntryActive)
                    .keyboardShortcut(.delete, modifiers: [])
                    .help("Delete selected annotations")
            }
            .buttonStyle(.plain)
            .foregroundColor(EditorColors.t1)

            Divider().frame(height: 20)

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

    /// The stamp slot: one button that behaves like the other tools on a plain click, with the
    /// other stamp kinds behind a long press or the marker in its bottom-right corner.
    ///
    /// The tick/cross/star stamps had no way to be reached at all before this. Giving each its own
    /// toolbar button worked but spent four slots on one tool, so they share this one instead.
    ///
    /// Deliberately a plain `Button` plus a `popover`, not a SwiftUI `Menu`. A `Menu` with
    /// `.borderlessButton` discards the label's overlays and background entirely — verified by
    /// rendering a 12pt red wedge that never appeared — so the corner marker and the selected-tool
    /// highlight both vanished, and its own indicator sat well off to the side of the glyph.
    var stampToolButton: some View {
        let tool = currentStampTool
        let active = selectedTool == tool
        return Button { selectedTool = tool } label: {
            Image(systemName: currentStampSymbol)
                .frame(width: 30, height: 30)
                .foregroundColor(active ? EditorColors.accent : EditorColors.t2)
                .background(active ? EditorColors.accent12 : Color.clear)
                .cornerRadius(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The corner wedge is its own button so it can be clicked directly, sitting above the
        // main one in the same corner. Padding around a 5pt marker gives it a usable hit area.
        .overlay(alignment: .bottomTrailing) {
            Button { showingStampAlternatives = true } label: {
                StampAlternativesIndicator()
                    .fill(active ? EditorColors.accent : EditorColors.t2)
                    .frame(width: 5, height: 5)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        // `.simultaneousGesture`, not `.onLongPressGesture`: the `Button` claims the press first,
        // so an ordinary long-press modifier never fires (verified — holding the icon only
        // selected the tool). A simultaneous gesture is recognised alongside the button's own.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3).onEnded { _ in showingStampAlternatives = true }
        )
        .popover(isPresented: $showingStampAlternatives, arrowEdge: .bottom) {
            stampAlternativesList
        }
        .help("Stamp — click to place, hold or click the corner to pick the next number or a tick / cross / star (7)")
    }

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

    /// The alternatives shown by the stamp slot's popover, each with the mark it places.
    private var stampAlternativesList: some View {
        VStack(alignment: .leading, spacing: 2) {
            stampAlternative(nil, symbol: "number.circle.fill", title: "Numbered step")
            nextNumberControl
            Divider().padding(.vertical, 2)
            stampAlternative(.check, symbol: "checkmark.circle.fill", title: "Tick")
            stampAlternative(.cross, symbol: "xmark.circle.fill", title: "Cross")
            stampAlternative(.star, symbol: "star.fill", title: "Star")
        }
        .padding(6)
        .frame(width: 220)
    }

    /// Which number the next numbered stamp places: type one, step it, or reset to 1.
    private var nextNumberControl: some View {
        HStack(spacing: 6) {
            Text("Next")
                .foregroundColor(.secondary)
            TextField("", value: Binding(
                get: { nextStampNumber },
                set: { number in
                    selectedStampKind = nil
                    setNextStampNumber(number)
                    selectedTool = numberTool
                }
            ), format: .number)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .frame(width: 48)
            Stepper("", value: Binding(
                get: { nextStampNumber },
                set: { number in
                    selectedStampKind = nil
                    setNextStampNumber(number)
                    selectedTool = numberTool
                }
            ), in: 1...Self.maxStampNumber)
            .labelsHidden()
            Spacer()
            Button("Reset") {
                selectedStampKind = nil
                setNextStampNumber(1)
                selectedTool = numberTool
            }
            .disabled(nextStampNumber == 1)
            .help("Start numbering again from 1")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func stampAlternative(_ kind: StampKind?, symbol: String, title: String) -> some View {
        let isCurrent = selectedStampKind == kind
        return Button {
            selectedStampKind = kind
            selectedTool = kind.map { .stamp($0) } ?? numberTool
            showingStampAlternatives = false
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

    /// The corner wedge marking a toolbar slot that has alternatives behind it: a right triangle
    /// filling the bottom-right, pointing into the corner.
    struct StampAlternativesIndicator: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }

    /// The stamp the slot currently represents: whichever kind was last picked from the menu, or
    /// the auto-incrementing numbered stamp by default.
    var currentStampTool: AnnotationTool {
        selectedStampKind.map { .stamp($0) } ?? numberTool
    }

    private var currentStampSymbol: String {
        switch selectedStampKind {
        case .check: return "checkmark.circle.fill"
        case .cross: return "xmark.circle.fill"
        case .star: return "star.fill"
        default: return stampKind(for: nextStampNumber).symbolName
        }
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
