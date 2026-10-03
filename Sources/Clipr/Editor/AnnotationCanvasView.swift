import SwiftUI
import Cocoa

/// Interactive canvas that lets the user drag out annotations on top of the captured image.
///
/// This type's implementation is split across several files by responsibility, all extensions of
/// this one struct (so member visibility below is `internal`, not `private`, purely so those
/// other files can see it — there is still exactly one component here):
/// - `AnnotationCanvasView.swift` (this file): properties, `body`, small shared helpers.
/// - `AnnotationCanvasView+Gestures.swift`: the main per-tool drag state machine.
/// - `AnnotationCanvasView+ResizeHandles.swift`: per-shape resize handles (selected or hovered).
/// - `AnnotationCanvasView+Hover.swift`: hover highlighting and the shared click hit test.
/// - `AnnotationCanvasView+LivePreview.swift`: the in-progress (not yet committed) drag preview.
/// - `AnnotationCanvasView+TextEditing.swift`: the live text-editing overlay.
///
/// Coordinate spaces: SwiftUI's `DragGesture` reports points in SwiftUI's own convention —
/// origin at the view's top-left, y increasing downward. `AnnotationRenderer` (which flattens
/// `AnnotationObject.frame` onto the base image) was empirically verified to interpret `frame`
/// in CoreGraphics' native convention instead — origin at the bottom-left, y increasing upward.
/// Every `AnnotationObject` this view constructs must therefore have its frame (and, for
/// freehand/arrow, its points) converted from SwiftUI space into that renderer space before
/// being stored in `annotations` — and converted back when reading a stored annotation's frame
/// (or points) for on-screen SwiftUI display. See `CanvasCoordinateSpace.swift` for the actual
/// conversion functions and why the same formula works both directions.
///
/// The in-progress live preview (while a drag is still active, before it commits into
/// `annotations`) is drawn directly in raw SwiftUI-space coordinates — it's never stored, so no
/// flip conversion applies to it.
struct AnnotationCanvasView: View {
    let image: NSImage
    @Binding var annotations: [AnnotationObject]
    @Binding var selectedTool: AnnotationTool
    @Binding var currentColor: RGBAColor
    var currentStrokeWidth: CGFloat
    @Binding var currentTextStyle: TextStyle
    /// Everything currently selected. Usually one annotation; several after Shift-click, a
    /// Select-tool marquee drag or ⌘A. Exposed so `EditorView`'s toolbar and shortcuts can act on it.
    @Binding var selectedIDs: Set<UUID>
    /// Exposed so `EditorView` can gate its number-key tool shortcuts — a bare "1"-"9" keypress
    /// must type into the text field being edited, not switch tools out from under it.
    @Binding var editingTextID: UUID?
    /// `EditorView`'s current zoom (1.0 == 100%) — used only to size the resize handles so they
    /// stay a constant, comfortably-clickable size on screen regardless of zoom, since this
    /// view itself renders at a fixed 1:1 image-point size and its parent applies the zoom via
    /// `.scaleEffect` outside it.
    var canvasScale: CGFloat = 1
    /// How far outside an annotation a click still counts as hitting it, in image points. Sized
    /// in screen terms (divided by zoom) so a zoomed-out large capture doesn't shrink thin arrows
    /// to a few unclickable pixels.
    var hitTolerance: CGFloat { 12 / max(canvasScale, 0.05) }

    /// The single selected annotation, or `nil` when nothing or several are selected — resize
    /// handles only make sense for one at a time.
    var soleSelectedID: UUID? { selectedIDs.count == 1 ? selectedIDs.first : nil }
    /// Style applied to redactions placed from now on — see the blur slot in
    /// `EditorView+Toolbar.swift`. Existing ones keep whatever they were created with.
    var redactionStyle: RedactionStyle = .pixelate
    /// Fired once, synchronously, right after a new annotation is appended — e.g. so a caller
    /// can auto-advance a numbered-stamp counter. Deliberately a direct callback at the exact
    /// moment of commit rather than something inferred later (like watching `annotations.count`
    /// change), so there's no dependency on view-update timing/ordering.
    var onAnnotationCommitted: ((AnnotationObject) -> Void)?
    /// Fired when a Crop drag completes, with the crop rect in renderer space. Cropping the
    /// actual base image is handled by the caller (it isn't an `AnnotationObject` — it changes
    /// `image` itself, which this view doesn't own).
    var onCropRequested: ((CGRect) -> Void)?

    @State var dragStart: CGPoint?
    @State var dragCurrentLocation: CGPoint?
    @State var freehandPoints: [CGPoint] = []
    /// The annotations being dragged right now — the whole selection when the drag started on
    /// one of its members, so a group moves together.
    @State var movingIDs: Set<UUID> = []
    @State var moveOffset: CGSize = .zero
    /// Set while a Select-tool drag that started on empty canvas is sweeping out a marquee.
    @State var isMarqueeSelecting = false
    @State var resizingID: UUID?
    /// The resizing annotation as it looks right now, updated continuously while a handle is
    /// dragged and committed back into `annotations` on release. A whole annotation rather than
    /// just a frame, because arrows and freehand strokes reshape their points too.
    @State var liveResized: AnnotationObject?
    /// The resize handle's own on-screen position at the moment its drag began, captured once
    /// and reused for the whole gesture. See `AnnotationCanvasView+ResizeHandles.swift`'s doc
    /// comment on `handleResizeChanged` for why re-reading the handle's (moving) current
    /// position every frame instead of this fixed anchor caused runaway, "far too sensitive"
    /// resizing.
    @State var resizeHandleAnchor: CGPoint?
    /// Set on the first gesture event that closes an actively-open text edit while the Text tool
    /// is still selected, so THIS SAME click doesn't also place a brand new text box — Snagit-
    /// style, clicking away from an edit just finishes it; placing a new one takes a separate,
    /// later click. See `AnnotationCanvasView+Gestures.swift`.
    @State var suppressTextPlacementForThisGesture = false
    /// The annotation currently under the mouse — shown with a hover highlight, a hand cursor and
    /// its resize handles, so it can be moved or resized straight away without selecting it
    /// first, and so it's clear that clicking here grabs the existing element instead of drawing
    /// a new one on top of it. `nil` while nothing is hovered, or while `.crop`/`.freehand` are
    /// active (they always act on whatever's under the whole gesture, not a specific element).
    @State var hoveredID: UUID?
    @FocusState var textFieldFocused: Bool

    /// The canvas fills `image` at 1:1, so the image's point height is also the canvas height —
    /// the value needed to flip between SwiftUI's y-down space and the renderer's y-up space.
    var canvasHeight: CGFloat { image.size.height }

    var displayColor: Color {
        Color(red: Double(currentColor.red), green: Double(currentColor.green), blue: Double(currentColor.blue), opacity: Double(currentColor.alpha))
    }

    /// Zero for every tool, so a plain click always reaches the gesture. SwiftUI's `DragGesture`
    /// never fires at all for a true zero-movement click when `minimumDistance` is 1: stamps and
    /// text need that click to place, and every tool needs it so clicking empty canvas clears the
    /// selection — with 1, a just-drawn arrow or box stayed selected no matter where you clicked.
    /// Each shape's commit already ignores a drag too small to have been deliberate.
    var dragMinimumDistance: CGFloat { 0 }

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)

            ForEach(annotations) { stored in
                // While a handle is being dragged, draw the live resized version instead.
                let annotation = stored.id == resizingID ? (liveResized ?? stored) : stored
                // The annotation currently being typed into is represented by the live text-
                // editing overlay below instead, so it isn't drawn twice.
                if annotation.id != editingTextID {
                    AnnotationOverlayShape(
                        annotation: annotation,
                        baseImage: image,
                        displayFrame: swiftUIFrame(fromRendererFrame: annotation.frame, canvasHeight: canvasHeight),
                        displayPoints: displayPoints(for: annotation),
                        isSelected: selectedIDs.contains(annotation.id),
                        isHovered: annotation.id == hoveredID,
                        liveOffset: movingIDs.contains(annotation.id) ? moveOffset : .zero
                    )
                }
            }

            ForEach(handleTargets) { target in
                resizeHandles(for: target)
            }

            livePreview
            textEditingOverlay
        }
        // Every y-flip in this view is only correct if the canvas actually renders at the
        // image's native point size. Pin it explicitly rather than trusting a parent view to
        // lay this out at exactly that size — a window resize or a different container could
        // otherwise silently desync canvasHeight from the view's real on-screen size and break
        // every coordinate conversion above.
        .frame(width: image.size.width, height: image.size.height)
        .gesture(
            DragGesture(minimumDistance: dragMinimumDistance)
                .onChanged { value in handleDragChanged(value) }
                .onEnded { value in handleDragEnded(value) }
        )
        .onContinuousHover { phase in handleHover(phase) }
    }
}
