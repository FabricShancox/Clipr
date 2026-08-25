import SwiftUI

/// Interactive canvas that lets the user drag out annotations on top of the captured image.
///
/// This type's implementation is split across several files by responsibility, all extensions of
/// this one struct (so member visibility below is `internal`, not `private`, purely so those
/// other files can see it — there is still exactly one component here):
/// - `AnnotationCanvasView.swift` (this file): properties, `body`, small shared helpers.
/// - `AnnotationCanvasView+Gestures.swift`: the main per-tool drag state machine.
/// - `AnnotationCanvasView+ResizeHandles.swift`: per-shape corner resize handles.
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
    @Binding var currentStrokeWidth: CGFloat
    @Binding var currentTextStyle: TextStyle
    /// Exposed so `EditorView`'s toolbar can offer a "Delete selected" action and know whether
    /// one exists to delete.
    @Binding var selectedID: UUID?
    /// Exposed so `EditorView` can gate its number-key tool shortcuts — a bare "1"-"9" keypress
    /// must type into the text field being edited, not switch tools out from under it.
    @Binding var editingTextID: UUID?
    /// `EditorView`'s current zoom (1.0 == 100%) — used only to size the resize handles so they
    /// stay a constant, comfortably-clickable size on screen regardless of zoom, since this
    /// view itself renders at a fixed 1:1 image-point size and its parent applies the zoom via
    /// `.scaleEffect` outside it.
    var canvasScale: CGFloat = 1
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
    @State var movingID: UUID?
    @State var moveOffset: CGSize = .zero
    @State var resizingID: UUID?
    @State var resizeCorner: ResizeCorner?
    /// The resizing annotation's live frame in SwiftUI display space, updated continuously while
    /// dragging a corner handle; committed back into `annotations` (in renderer space) on release.
    @State var liveResizeFrame: CGRect?
    @FocusState var textFieldFocused: Bool

    /// The canvas fills `image` at 1:1, so the image's point height is also the canvas height —
    /// the value needed to flip between SwiftUI's y-down space and the renderer's y-up space.
    var canvasHeight: CGFloat { image.size.height }

    var displayColor: Color {
        Color(red: Double(currentColor.red), green: Double(currentColor.green), blue: Double(currentColor.blue), opacity: Double(currentColor.alpha))
    }

    /// Stamps and text place on a single click; the Select tool also needs a plain click (with
    /// zero movement) to register as a selection. Every other tool needs an actual drag to size
    /// what it's drawing. SwiftUI's `DragGesture` never fires `onEnded` for a true zero-movement
    /// click when `minimumDistance` is 1, which is why these felt like they required a tiny drag
    /// even though nothing was meant to be sized.
    var dragMinimumDistance: CGFloat {
        switch selectedTool {
        case .stamp, .text, .select: return 0
        default: return 1
        }
    }

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)

            ForEach(annotations) { annotation in
                // The annotation currently being typed into is represented by the live text-
                // editing overlay below instead, so it isn't drawn twice.
                if annotation.id != editingTextID {
                    AnnotationOverlayShape(
                        annotation: annotation,
                        displayFrame: annotation.id == resizingID
                            ? (liveResizeFrame ?? swiftUIFrame(fromRendererFrame: annotation.frame, canvasHeight: canvasHeight))
                            : swiftUIFrame(fromRendererFrame: annotation.frame, canvasHeight: canvasHeight),
                        displayPoints: displayPoints(for: annotation),
                        isSelected: annotation.id == selectedID,
                        liveOffset: annotation.id == movingID ? moveOffset : .zero
                    )
                }
            }

            if let id = selectedID, let selected = annotations.first(where: { $0.id == id }),
               resizeHandlesApply(to: selected), selected.id != editingTextID {
                resizeHandles(for: selected)
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
    }

    /// Resize handles only make sense for annotations whose geometry is a plain rectangular
    /// frame — `.freehand`/`.arrow` store their own explicit point lists, so resizing "the
    /// frame" wouldn't resize the actual stroke.
    func resizeHandlesApply(to annotation: AnnotationObject) -> Bool {
        switch annotation.kind {
        case .freehand, .arrow: return false
        default: return true
        }
    }

    func rectBetween(_ start: CGPoint, _ current: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y)
        )
    }
}
