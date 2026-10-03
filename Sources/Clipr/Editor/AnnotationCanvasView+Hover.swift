import SwiftUI
import Cocoa

/// Hover handling: hovering over an EXISTING annotation highlights it, shows its resize handles
/// and switches the cursor, so it can be moved or resized straight away and it's clear before
/// clicking that this grabs that element rather than drawing a new one on top of it. Also the
/// shared hit test the drag gesture uses. See `AnnotationCanvasView.swift`'s header for how this
/// file relates to the rest of the type.
extension AnnotationCanvasView {
    func handleHover(_ phase: HoverPhase) {
        guard hoverPromptApplies else {
            setHovered(nil)
            return
        }
        switch phase {
        case .active(let location):
            // Leave the highlight alone mid-drag; the gesture owns the cursor until it ends.
            guard resizingID == nil, movingIDs.isEmpty, !isMarqueeSelecting else { return }
            setHovered(annotation(atSwiftUIPoint: location)?.id)
        case .ended:
            setHovered(nil)
        }
    }

    /// The annotation a click at `location` grabs. Among overlapping hits the smallest wins, so
    /// an arrow or stamp lying inside a large box or highlight is still reachable; on a tie the
    /// topmost (last drawn) wins. With a drawing tool, a hollow box or ellipse is only grabbed by
    /// its outline, so a click in its empty middle draws instead; Select grabs it anywhere.
    func annotation(atSwiftUIPoint location: CGPoint) -> AnnotationObject? {
        let point = rendererPoint(fromSwiftUIPoint: location, canvasHeight: canvasHeight)
        let grabsInterior = selectedTool == .select
        return annotations
            .reversed()
            .filter {
                grabsInterior
                    ? $0.contains(point, tolerance: hitTolerance)
                    : $0.outlineContains(point, tolerance: hitTolerance)
            }
            .min { $0.hitArea < $1.hitArea }
    }

    /// Crop and Freehand always act on the whole gesture rather than a specific existing
    /// element, so neither offers to grab what's under the mouse.
    private var hoverPromptApplies: Bool {
        switch selectedTool {
        case .crop, .freehand: return false
        default: return true
        }
    }

    /// Open hand with Select (dragging moves), pointing hand with a drawing tool (clicking grabs
    /// this element instead of drawing).
    var hoverCursor: NSCursor { selectedTool == .select ? .openHand : .pointingHand }

    private func setHovered(_ id: UUID?) {
        guard id != hoveredID else { return }
        hoveredID = id
        if id != nil { hoverCursor.set() } else { NSCursor.arrow.set() }
    }
}
