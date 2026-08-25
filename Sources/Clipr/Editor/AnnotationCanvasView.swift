import SwiftUI

enum AnnotationTool: Equatable {
    case select, rectangle, ellipse, arrow, freehand, text, highlighter, blur, crop, stamp(StampKind)
}

/// Interactive canvas that lets the user drag out annotations on top of the captured image.
///
/// Coordinate spaces: SwiftUI's `DragGesture` reports points in SwiftUI's own convention —
/// origin at the view's top-left, y increasing downward. `AnnotationRenderer` (which flattens
/// `AnnotationObject.frame` onto the base image) was empirically verified to interpret `frame`
/// in CoreGraphics' native convention instead — origin at the bottom-left, y increasing upward
/// (see `AnnotationRenderer`'s `flipped: false` NSGraphicsContext, which matches CGContext's
/// bottom-left-origin default). Every `AnnotationObject` this view constructs must therefore have
/// its frame (and, for freehand/arrow, its points) converted from SwiftUI space into that
/// renderer space before being stored in `annotations` — and converted back when reading a
/// stored annotation's frame (or points) for on-screen SwiftUI display (e.g. the selection
/// outline). Both conversions use the same formula, `y' = canvasHeight - y - height` for rects
/// (or `y' = canvasHeight - y` for bare points), because that formula is its own inverse.
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
    /// Fired once, synchronously, right after a new annotation is appended — e.g. so a caller
    /// can auto-advance a numbered-stamp counter. Deliberately a direct callback at the exact
    /// moment of commit rather than something inferred later (like watching `annotations.count`
    /// change), so there's no dependency on view-update timing/ordering.
    var onAnnotationCommitted: ((AnnotationObject) -> Void)?
    /// Fired when a Crop drag completes, with the crop rect in renderer space. Cropping the
    /// actual base image is handled by the caller (it isn't an `AnnotationObject` — it changes
    /// `image` itself, which this view doesn't own).
    var onCropRequested: ((CGRect) -> Void)?

    @State private var dragStart: CGPoint?
    @State private var dragCurrentLocation: CGPoint?
    @State private var freehandPoints: [CGPoint] = []
    @State private var selectedID: UUID?
    @State private var movingID: UUID?
    @State private var moveOffset: CGSize = .zero
    @State private var editingTextID: UUID?
    @FocusState private var textFieldFocused: Bool

    /// The canvas fills `image` at 1:1, so the image's point height is also the canvas height —
    /// the value needed to flip between SwiftUI's y-down space and the renderer's y-up space.
    private var canvasHeight: CGFloat { image.size.height }

    private var displayColor: Color {
        Color(red: Double(currentColor.red), green: Double(currentColor.green), blue: Double(currentColor.blue), opacity: Double(currentColor.alpha))
    }

    /// Stamps and text place on a single click; every other tool needs an actual drag to size
    /// what it's drawing. SwiftUI's `DragGesture` never fires `onEnded` for a true zero-movement
    /// click when `minimumDistance` is 1, which is why stamps/text used to feel like they
    /// required a tiny drag even though nothing was meant to be sized.
    private var dragMinimumDistance: CGFloat {
        switch selectedTool {
        case .stamp, .text: return 0
        default: return 1
        }
    }

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)

            ForEach(annotations) { annotation in
                // The annotation currently being typed into is represented by the live
                // `TextField` overlay below instead, so it isn't drawn twice.
                if annotation.id != editingTextID {
                    AnnotationOverlayShape(
                        annotation: annotation,
                        displayFrame: swiftUIFrame(fromRendererFrame: annotation.frame),
                        displayPoints: displayPoints(for: annotation),
                        isSelected: annotation.id == selectedID,
                        liveOffset: annotation.id == movingID ? moveOffset : .zero
                    )
                }
            }

            livePreview
            textEditingOverlay
        }
        // Every y-flip in this view is only correct if the canvas actually renders at the
        // image's native point size. Pin it explicitly rather than trusting a parent view
        // (e.g. EditorView, Task 14) to lay this out at exactly that size — a window resize
        // or a different container could otherwise silently desync canvasHeight from the
        // view's real on-screen size and break every coordinate conversion above.
        .frame(width: image.size.width, height: image.size.height)
        .gesture(
            DragGesture(minimumDistance: dragMinimumDistance)
                .onChanged { value in handleDragChanged(value) }
                .onEnded { value in handleDragEnded(value) }
        )
    }

    /// What the user is actively drawing right now, before it commits into `annotations` on
    /// drag-end. Drawn in raw SwiftUI-space coordinates (never stored, so no flip needed).
    @ViewBuilder
    private var livePreview: some View {
        switch selectedTool {
        case .freehand:
            if !freehandPoints.isEmpty {
                livePath(freehandPoints)
                    .stroke(displayColor, style: StrokeStyle(lineWidth: currentStrokeWidth, lineCap: .round, lineJoin: .round))
            }
        case .arrow:
            if let start = dragStart, let current = dragCurrentLocation {
                arrowPath(from: start, to: current, strokeWidth: currentStrokeWidth)
                    .stroke(displayColor, lineWidth: currentStrokeWidth)
            }
        case .rectangle, .ellipse, .highlighter, .blur:
            if let start = dragStart, let current = dragCurrentLocation {
                liveShapePreview(for: selectedTool, in: rectBetween(start, current))
            }
        case .crop:
            if let start = dragStart, let current = dragCurrentLocation {
                Rectangle()
                    .strokeBorder(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .background(Color.black.opacity(0.15))
                    .frame(width: rectBetween(start, current).width, height: rectBetween(start, current).height)
                    .position(x: rectBetween(start, current).midX, y: rectBetween(start, current).midY)
            }
        default:
            EmptyView()
        }
    }

    private func rectBetween(_ start: CGPoint, _ current: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(current.x - start.x), height: abs(current.y - start.y)
        )
    }

    @ViewBuilder
    private func liveShapePreview(for tool: AnnotationTool, in rect: CGRect) -> some View {
        switch tool {
        case .rectangle:
            Rectangle().stroke(displayColor, lineWidth: currentStrokeWidth)
                .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        case .ellipse:
            Ellipse().stroke(displayColor, lineWidth: currentStrokeWidth)
                .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        case .highlighter:
            Rectangle().fill(displayColor.opacity(0.35))
                .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        case .blur:
            Rectangle().fill(Color(white: 0.5, opacity: 0.9))
                .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        default:
            EmptyView()
        }
    }

    private func livePath(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    /// While `editingTextID` is set, a real `TextField` sits directly over that annotation's
    /// frame so the user can type. Bound straight through to the stored `.text` payload (via
    /// `editingTextBinding`) rather than a separate local buffer, so every keystroke is already
    /// "saved" into `annotations` — closing the editor (Return, or starting any other gesture)
    /// never needs a separate commit step.
    @ViewBuilder
    private var textEditingOverlay: some View {
        if let id = editingTextID, let annotation = annotations.first(where: { $0.id == id }),
           case .text(_, let style) = annotation.kind {
            let frame = swiftUIFrame(fromRendererFrame: annotation.frame)
            TextField("", text: editingTextBinding)
                .textFieldStyle(.plain)
                .font(styledSwiftUIFont(style))
                .foregroundColor(displayColor(for: annotation))
                .frame(width: max(frame.width, 80), height: frame.height, alignment: .leading)
                .position(x: max(frame.width, 80) / 2 + frame.minX, y: frame.midY)
                .focused($textFieldFocused)
                .onSubmit { editingTextID = nil }
                .onAppear { textFieldFocused = true }
        }
    }

    private func displayColor(for annotation: AnnotationObject) -> Color {
        Color(
            red: Double(annotation.color.red), green: Double(annotation.color.green),
            blue: Double(annotation.color.blue), opacity: Double(annotation.color.alpha)
        )
    }

    private var editingTextBinding: Binding<String> {
        Binding(
            get: {
                guard let id = editingTextID, let annotation = annotations.first(where: { $0.id == id }),
                      case .text(let string, _) = annotation.kind else { return "" }
                return string
            },
            set: { newValue in
                guard let id = editingTextID, let index = annotations.firstIndex(where: { $0.id == id }),
                      case .text(_, let style) = annotations[index].kind else { return }
                annotations[index].kind = .text(newValue, style)
            }
        )
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        // Starting any new gesture — anywhere, with any tool — closes whatever text field was
        // open. Its content is already live-written via `editingTextBinding`, so this never
        // loses anything; it just returns the canvas to its normal (non-editing) state.
        if editingTextID != nil { editingTextID = nil }

        switch selectedTool {
        case .freehand:
            freehandPoints.append(value.location)
        case .select:
            if dragStart == nil {
                // Decide once, at the start of this drag, whether we're moving the already-
                // selected annotation (the drag started on top of it) or just about to tap
                // somewhere to change the selection.
                let rendererPoint = rendererPoint(fromSwiftUIPoint: value.startLocation)
                if let selectedID, let selected = annotations.first(where: { $0.id == selectedID }),
                   selected.contains(rendererPoint) {
                    movingID = selectedID
                }
                dragStart = value.startLocation
            }
            if movingID != nil {
                moveOffset = CGSize(width: value.location.x - value.startLocation.x, height: value.location.y - value.startLocation.y)
            }
        default:
            if dragStart == nil { dragStart = value.startLocation }
            dragCurrentLocation = value.location
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        switch selectedTool {
        case .select:
            if let movingID, let index = annotations.firstIndex(where: { $0.id == movingID }) {
                // SwiftUI's drag delta is in y-down space; the stored geometry is in the
                // renderer's y-up space, so the y component of the delta flips sign too.
                let rendererDelta = CGPoint(x: moveOffset.width, y: -moveOffset.height)
                annotations[index] = translated(annotations[index], byRendererDelta: rendererDelta)
            } else {
                let rendererPoint = rendererPoint(fromSwiftUIPoint: value.location)
                selectedID = annotations.last { $0.contains(rendererPoint) }?.id
            }
            movingID = nil
            moveOffset = .zero
            dragStart = nil
        case .freehand:
            guard !freehandPoints.isEmpty else { return }
            let rendererPoints = freehandPoints.map { rendererPoint(fromSwiftUIPoint: $0) }
            commit(AnnotationObject(
                id: UUID(), kind: .freehand(rendererPoints),
                frame: boundingBox(of: rendererPoints),
                color: currentColor, strokeWidth: currentStrokeWidth
            ))
            freehandPoints = []
        case .text:
            let start = dragStart ?? value.location
            let swiftUIFrame = CGRect(x: start.x, y: start.y, width: 160, height: currentTextStyle.fontSize + 10)
            let newAnnotation = AnnotationObject(
                id: UUID(), kind: .text("", currentTextStyle),
                frame: rendererFrame(fromSwiftUIFrame: swiftUIFrame),
                color: currentColor, strokeWidth: currentStrokeWidth
            )
            commit(newAnnotation)
            editingTextID = newAnnotation.id
            dragStart = nil
            dragCurrentLocation = nil
        case .stamp(let kind):
            let swiftUIFrame = CGRect(x: value.location.x - 16, y: value.location.y - 16, width: 32, height: 32)
            commit(AnnotationObject(
                id: UUID(), kind: .stamp(kind),
                frame: rendererFrame(fromSwiftUIFrame: swiftUIFrame),
                color: currentColor, strokeWidth: currentStrokeWidth
            ))
            // handleDragChanged's `default:` branch sets `dragStart` for any tool it doesn't
            // explicitly case (which includes .stamp, since a stamp is placed on drag-end, not
            // dragged out like a rect). Without this reset, a stale dragStart from placing a
            // stamp would corrupt the START POINT of the next rectangle/arrow/text/highlighter/
            // blur drag.
            dragStart = nil
            dragCurrentLocation = nil
        case .arrow:
            guard let start = dragStart else { return }
            let rendererStart = rendererPoint(fromSwiftUIPoint: start)
            let rendererEnd = rendererPoint(fromSwiftUIPoint: value.location)
            dragStart = nil
            dragCurrentLocation = nil
            guard hypot(value.location.x - start.x, value.location.y - start.y) > 2 else { return }
            commit(AnnotationObject(
                id: UUID(), kind: .arrow(rendererStart, rendererEnd),
                frame: boundingBox(of: [rendererStart, rendererEnd]),
                color: currentColor, strokeWidth: currentStrokeWidth
            ))
        case .crop:
            guard let start = dragStart else { return }
            let swiftUIFrame = rectBetween(start, value.location)
            dragStart = nil
            dragCurrentLocation = nil
            guard swiftUIFrame.width > 4, swiftUIFrame.height > 4 else { return }
            onCropRequested?(rendererFrame(fromSwiftUIFrame: swiftUIFrame))
        default:
            guard let start = dragStart else { return }
            let swiftUIFrame = rectBetween(start, value.location)
            dragStart = nil
            dragCurrentLocation = nil
            guard swiftUIFrame.width > 2, swiftUIFrame.height > 2 else { return }
            let kind: AnnotationKind
            switch selectedTool {
            case .ellipse: kind = .ellipse
            case .highlighter: kind = .highlighter
            case .blur: kind = .blur
            default: kind = .rectangle
            }
            commit(AnnotationObject(
                id: UUID(), kind: kind,
                frame: rendererFrame(fromSwiftUIFrame: swiftUIFrame),
                color: currentColor, strokeWidth: currentStrokeWidth
            ))
        }
    }

    private func commit(_ annotation: AnnotationObject) {
        annotations.append(annotation)
        onAnnotationCommitted?(annotation)
    }

    /// Moves an annotation by a delta already expressed in renderer space, translating whichever
    /// point data that annotation kind actually stores (not just `frame`, which is only a
    /// bounding box for `.freehand`/`.arrow` — moving those without also translating their real
    /// points would leave the stroke behind while the (invisible) frame moved).
    private func translated(_ annotation: AnnotationObject, byRendererDelta delta: CGPoint) -> AnnotationObject {
        var copy = annotation
        copy.frame = annotation.frame.offsetBy(dx: delta.x, dy: delta.y)
        switch annotation.kind {
        case .freehand(let points):
            copy.kind = .freehand(points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) })
        case .arrow(let start, let end):
            copy.kind = .arrow(
                CGPoint(x: start.x + delta.x, y: start.y + delta.y),
                CGPoint(x: end.x + delta.x, y: end.y + delta.y)
            )
        default:
            break // frame move alone is enough for rectangle/ellipse/highlighter/blur/text/stamp
        }
        return copy
    }

    private func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Per-annotation-kind points needed by `AnnotationOverlayShape` for live rendering, already
    /// converted into SwiftUI display space:
    /// - `.freehand`: every stored (renderer-space) point, converted for the stroke path.
    /// - `.arrow`: the two explicit renderer-space endpoints, converted, so the displayed arrow
    ///   points the same direction the user actually dragged (see `AnnotationKind.arrow`'s doc).
    /// - everything else: unused by the shape, so empty.
    private func displayPoints(for annotation: AnnotationObject) -> [CGPoint] {
        switch annotation.kind {
        case .freehand(let points):
            return points.map { swiftUIPoint(fromRendererPoint: $0) }
        case .arrow(let start, let end):
            return [swiftUIPoint(fromRendererPoint: start), swiftUIPoint(fromRendererPoint: end)]
        default:
            return []
        }
    }

    // MARK: - Coordinate space conversion (SwiftUI y-down <-> renderer y-up)

    /// Converts a rect from SwiftUI's y-down space (as reported by `DragGesture`) into the
    /// y-up-from-bottom space `AnnotationRenderer` expects to find in `AnnotationObject.frame`.
    private func rendererFrame(fromSwiftUIFrame swiftUIFrame: CGRect) -> CGRect {
        CGRect(
            x: swiftUIFrame.origin.x,
            y: canvasHeight - swiftUIFrame.origin.y - swiftUIFrame.height,
            width: swiftUIFrame.width,
            height: swiftUIFrame.height
        )
    }

    /// Converts a stored renderer-space frame back into SwiftUI's y-down space for on-screen
    /// display. This is the exact same formula as `rendererFrame(fromSwiftUIFrame:)` — the
    /// flip is its own inverse for a rect of fixed height — kept as a separate, clearly-named
    /// function at the call site so the direction of each conversion is unambiguous.
    private func swiftUIFrame(fromRendererFrame rendererFrame: CGRect) -> CGRect {
        CGRect(
            x: rendererFrame.origin.x,
            y: canvasHeight - rendererFrame.origin.y - rendererFrame.height,
            width: rendererFrame.width,
            height: rendererFrame.height
        )
    }

    /// Converts a single point from SwiftUI's y-down space into renderer y-up space.
    private func rendererPoint(fromSwiftUIPoint point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: canvasHeight - point.y)
    }

    /// Converts a single point from renderer y-up space back into SwiftUI's y-down display
    /// space. Symmetric to (and the same formula as) `rendererPoint(fromSwiftUIPoint:)`.
    private func swiftUIPoint(fromRendererPoint point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: canvasHeight - point.y)
    }
}

/// Shared by the live (in-progress) arrow preview and the committed `AnnotationOverlayShape`
/// arrow rendering, so both draw the exact same head geometry.
func arrowPath(from start: CGPoint, to end: CGPoint, strokeWidth: CGFloat) -> Path {
    Path { path in
        path.move(to: start)
        path.addLine(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = arrowHeadLength(for: strokeWidth)
        let p1 = CGPoint(x: end.x - headLength * cos(angle - .pi / 6), y: end.y - headLength * sin(angle - .pi / 6))
        let p2 = CGPoint(x: end.x - headLength * cos(angle + .pi / 6), y: end.y - headLength * sin(angle + .pi / 6))
        path.move(to: end)
        path.addLine(to: p1)
        path.move(to: end)
        path.addLine(to: p2)
    }
}

/// `TextStyle` -> SwiftUI `Font`, matching `styledFont(_:)`'s AppKit `NSFont` construction used
/// by `AnnotationRenderer` and the live `TextField` overlay, so what you see while typing matches
/// what gets flattened into the saved image.
func styledSwiftUIFont(_ style: TextStyle) -> Font {
    var font = Font.system(size: style.fontSize)
    if style.bold { font = font.bold() }
    if style.italic { font = font.italic() }
    return font
}

/// Renders one annotation's live, in-progress appearance on the canvas (so the user sees what
/// they're drawing immediately, without waiting for `AnnotationRenderer.flatten` to run), plus
/// its selection outline on top. This is a lightweight SwiftUI approximation of what
/// `AnnotationRenderer` will eventually flatten onto the image — it does not need to be
/// pixel-identical to that final render, only visibly represent each annotation kind.
private struct AnnotationOverlayShape: View {
    let annotation: AnnotationObject
    /// `annotation.frame` already converted into SwiftUI's y-down display space.
    let displayFrame: CGRect
    /// Extra points needed for `.freehand` (the full stroke, converted) and `.arrow` (the two
    /// endpoints, converted) — see `AnnotationCanvasView.displayPoints(for:)`. Empty for kinds
    /// that don't need it.
    let displayPoints: [CGPoint]
    let isSelected: Bool
    /// Live drag offset while this specific annotation is being moved (Select tool); `.zero`
    /// otherwise. Applied as a plain view-space translation on top of the normal position.
    var liveOffset: CGSize = .zero

    private var color: Color {
        Color(
            red: Double(annotation.color.red),
            green: Double(annotation.color.green),
            blue: Double(annotation.color.blue),
            opacity: Double(annotation.color.alpha)
        )
    }

    var body: some View {
        ZStack {
            content
            selectionOutline
        }
        .offset(liveOffset)
    }

    @ViewBuilder
    private var content: some View {
        switch annotation.kind {
        case .rectangle:
            Rectangle()
                .stroke(color, lineWidth: annotation.strokeWidth)
                .frame(width: displayFrame.width, height: displayFrame.height)
                .position(x: displayFrame.midX, y: displayFrame.midY)
        case .ellipse:
            Ellipse()
                .stroke(color, lineWidth: annotation.strokeWidth)
                .frame(width: displayFrame.width, height: displayFrame.height)
                .position(x: displayFrame.midX, y: displayFrame.midY)
        case .arrow:
            if displayPoints.count == 2 {
                arrowPath(from: displayPoints[0], to: displayPoints[1], strokeWidth: annotation.strokeWidth)
                    .stroke(color, lineWidth: annotation.strokeWidth)
            }
        case .freehand:
            freehandPath
                .stroke(color, style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round, lineJoin: .round))
        case .text(let string, let style):
            Text(string)
                .font(styledSwiftUIFont(style))
                .foregroundColor(color)
                .frame(width: displayFrame.width, height: displayFrame.height, alignment: .leading)
                .position(x: displayFrame.midX, y: displayFrame.midY)
        case .highlighter:
            Rectangle()
                .fill(color.opacity(0.35))
                .frame(width: displayFrame.width, height: displayFrame.height)
                .position(x: displayFrame.midX, y: displayFrame.midY)
        case .blur:
            // Matches AnnotationRenderer's own v1 approximation: a flat translucent gray box
            // rather than a real pixel-sampling blur.
            Rectangle()
                .fill(Color(white: 0.5, opacity: 0.9))
                .frame(width: displayFrame.width, height: displayFrame.height)
                .position(x: displayFrame.midX, y: displayFrame.midY)
        case .stamp(let kind):
            Image(systemName: kind.symbolName)
                .resizable()
                .scaledToFit()
                .foregroundColor(color)
                .frame(width: displayFrame.width, height: displayFrame.height)
                .position(x: displayFrame.midX, y: displayFrame.midY)
        }
    }

    private var selectionOutline: some View {
        Rectangle()
            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            .frame(width: displayFrame.width, height: displayFrame.height)
            .position(x: displayFrame.midX, y: displayFrame.midY)
    }

    private var freehandPath: Path {
        Path { path in
            guard let first = displayPoints.first else { return }
            path.move(to: first)
            for point in displayPoints.dropFirst() {
                path.addLine(to: point)
            }
        }
    }
}
