import SwiftUI

/// Color/stroke bindings that retarget to whatever's selected. See `EditorView.swift`'s header
/// for how this file relates to the rest of the type.
extension EditorView {
    /// The binding the color swatches actually edit: the selected annotation's own color (any
    /// kind, not just text) when one is selected — so clicking a swatch restyles what's
    /// selected, matching a normal editor — otherwise `currentColor` (the default applied to
    /// the next annotation drawn).
    var colorBinding: Binding<RGBAColor> {
        guard let id = selectedAnnotationID else { return $currentColor }
        return Binding(
            get: { annotations.first(where: { $0.id == id })?.color ?? currentColor },
            set: { newColor in
                mutateAnnotations { list in
                    guard let index = list.firstIndex(where: { $0.id == id }) else { return }
                    list[index].color = newColor
                }
            }
        )
    }

    /// Same reasoning as `colorBinding`, for stroke width.
    var strokeWidthBinding: Binding<CGFloat> {
        guard let id = selectedAnnotationID else { return $currentStrokeWidth }
        return Binding(
            get: { annotations.first(where: { $0.id == id })?.strokeWidth ?? currentStrokeWidth },
            set: { newWidth in
                mutateAnnotations { list in
                    guard let index = list.firstIndex(where: { $0.id == id }) else { return }
                    list[index].strokeWidth = newWidth
                }
            }
        )
    }
}
