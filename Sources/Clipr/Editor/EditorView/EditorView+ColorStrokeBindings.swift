import SwiftUI

/// Color/stroke bindings that retarget to whatever's selected. See `EditorView.swift`'s header
/// for how this file relates to the rest of the type.
extension EditorView {
    /// Thin / Medium / Thick.
    static let strokePresets: [CGFloat] = [2, 4, 8]

    /// The binding the color swatches actually edit: the selected annotations' own color (any
    /// kind, not just text) when something is selected — so clicking a swatch restyles what's
    /// selected, matching a normal editor. The pick also becomes `currentColor` (the default for
    /// the next annotation drawn), so restyling a shape and then drawing another carries on in
    /// the same colour rather than silently reverting to whatever was picked before.
    var colorBinding: Binding<RGBAColor> {
        guard !selectedIDs.isEmpty else { return $currentColor }
        let ids = selectedIDs
        return Binding(
            get: { annotations.first(where: { ids.contains($0.id) })?.color ?? currentColor },
            set: { newColor in
                currentColor = newColor
                mutateAnnotations { list in
                    for index in list.indices where ids.contains(list[index].id) {
                        list[index].color = newColor
                    }
                }
            }
        )
    }

    /// Same reasoning as `colorBinding`, for stroke width. A stamp has no outline, so for one the
    /// preset sets its size instead, resized about its centre so it stays where it was placed.
    var strokeWidthBinding: Binding<CGFloat> {
        guard !selectedIDs.isEmpty else { return $currentStrokeWidth }
        let ids = selectedIDs
        return Binding(
            get: { annotations.first(where: { ids.contains($0.id) })?.strokeWidth ?? currentStrokeWidth },
            set: { preset in
                currentStrokeWidth = preset
                mutateAnnotations { list in
                    for index in list.indices where ids.contains(list[index].id) {
                        list[index].strokeWidth = preset
                        if case .stamp = list[index].kind {
                            let frame = list[index].frame
                            let side = StampKind.side(forStrokeWidth: preset)
                            list[index].frame = CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side)
                        }
                    }
                }
            }
        )
    }

    /// Steps to the next thinner/thicker preset — bound to `[` and `]`. Starts from whichever
    /// preset is nearest, in case a shape's width sits between them.
    func stepStrokeWidth(by step: Int) {
        let presets = Self.strokePresets
        let current = strokeWidthBinding.wrappedValue
        let nearest = presets.indices.min { abs(presets[$0] - current) < abs(presets[$1] - current) } ?? 1
        let next = presets[min(max(nearest + step, 0), presets.count - 1)]
        guard abs(next - current) > 0.01 else { return }
        strokeWidthBinding.wrappedValue = next
    }
}
