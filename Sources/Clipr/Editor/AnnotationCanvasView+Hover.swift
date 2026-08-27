import SwiftUI
import Cocoa

/// Hover-to-select prompting: while a non-Select drawing tool is active, hovering over an
/// EXISTING annotation highlights it and switches the cursor to a pointing hand, so it's clear
/// before clicking that this will select that element rather than draw a new one on top of it.
/// See `AnnotationCanvasView.swift`'s header for how this file relates to the rest of the type.
extension AnnotationCanvasView {
    func handleHover(_ phase: HoverPhase) {
        guard hoverPromptApplies else {
            setHovered(nil)
            return
        }
        switch phase {
        case .active(let location):
            let point = rendererPoint(fromSwiftUIPoint: location, canvasHeight: canvasHeight)
            setHovered(annotations.last(where: { $0.contains(point) })?.id)
        case .ended:
            setHovered(nil)
        }
    }

    /// Select's own selection UI already communicates "click to grab this"; Crop and Freehand
    /// always act on the whole gesture rather than a specific existing element, so neither needs
    /// this prompt either.
    private var hoverPromptApplies: Bool {
        switch selectedTool {
        case .select, .crop, .freehand: return false
        default: return true
        }
    }

    private func setHovered(_ id: UUID?) {
        guard id != hoveredID else { return }
        hoveredID = id
        if id != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    }
}
