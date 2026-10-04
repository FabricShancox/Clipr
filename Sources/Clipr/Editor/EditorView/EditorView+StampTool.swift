import SwiftUI

/// The toolbar's stamp slot and its popover of alternatives (numbered step, tick, cross, star).
extension EditorView {
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
        .accessibilityLabel("Stamp (7)")
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
}
