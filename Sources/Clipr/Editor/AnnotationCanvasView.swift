import SwiftUI

enum AnnotationTool: Equatable {
    case select, rectangle, arrow, freehand, text, highlighter, blur, stamp(StampKind)
}

/// Interactive canvas that lets the user drag out annotations on top of the captured image.
///
/// Coordinate spaces: SwiftUI's `DragGesture` reports points in SwiftUI's own convention —
/// origin at the view's top-left, y increasing downward. `AnnotationRenderer` (which flattens
/// `AnnotationObject.frame` onto the base image) was empirically verified to interpret `frame`
/// in CoreGraphics' native convention instead — origin at the bottom-left, y increasing upward
/// (see `AnnotationRenderer`'s `flipped: false` NSGraphicsContext, which matches CGContext's
/// bottom-left-origin default). Every `AnnotationObject` this view constructs must therefore have
/// its frame (and, for freehand, its points) converted from SwiftUI space into that renderer
/// space before being stored in `annotations` — and converted back when reading a stored
/// annotation's frame (or points) for on-screen SwiftUI display (e.g. the live preview and the
/// selection outline). Both conversions use the same formula, `y' = canvasHeight - y - height`
/// for rects (or `y' = canvasHeight - y` for bare points), because that formula is its own
/// inverse.
struct AnnotationCanvasView: View {
    let image: NSImage
    @Binding var annotations: [AnnotationObject]
    @Binding var selectedTool: AnnotationTool
    @Binding var currentColor: RGBAColor
    @Binding var currentStrokeWidth: CGFloat

    @State private var dragStart: CGPoint?
    @State private var freehandPoints: [CGPoint] = []
    @State private var selectedID: UUID?

    /// The canvas fills `image` at 1:1, so the image's point height is also the canvas height —
    /// the value needed to flip between SwiftUI's y-down space and the renderer's y-up space.
    private var canvasHeight: CGFloat { image.size.height }

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)

            ForEach(annotations) { annotation in
                AnnotationOverlayShape(
                    annotation: annotation,
                    displayFrame: swiftUIFrame(fromRendererFrame: annotation.frame),
                    displayPoints: displayPoints(for: annotation),
                    isSelected: annotation.id == selectedID
                )
            }
        }
        // Every y-flip in this view is only correct if the canvas actually renders at the
        // image's native point size. Pin it explicitly rather than trusting a parent view
        // (e.g. EditorView, Task 14) to lay this out at exactly that size — a window resize
        // or a different container could otherwise silently desync canvasHeight from the
        // view's real on-screen size and break every coordinate conversion above.
        .frame(width: image.size.width, height: image.size.height)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in handleDragChanged(value) }
                .onEnded { value in handleDragEnded(value) }
        )
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        switch selectedTool {
        case .freehand:
            freehandPoints.append(value.location)
        case .select:
            break
        default:
            if dragStart == nil { dragStart = value.startLocation }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        switch selectedTool {
        case .select:
            let rendererPoint = rendererPoint(fromSwiftUIPoint: value.location)
            selectedID = annotations.last { $0.contains(rendererPoint) }?.id
        case .freehand:
            guard !freehandPoints.isEmpty else { return }
            let rendererPoints = freehandPoints.map { rendererPoint(fromSwiftUIPoint: $0) }
            annotations.append(AnnotationObject(
                id: UUID(), kind: .freehand(rendererPoints),
                frame: boundingBox(of: rendererPoints),
                color: currentColor, strokeWidth: currentStrokeWidth
            ))
            freehandPoints = []
        case .text:
            guard let start = dragStart else { return }
            let swiftUIFrame = CGRect(x: start.x, y: start.y, width: 120, height: 24)
            annotations.append(AnnotationObject(
                id: UUID(), kind: .text("Text"),
                frame: rendererFrame(fromSwiftUIFrame: swiftUIFrame),
                color: currentColor, strokeWidth: currentStrokeWidth
            ))
            dragStart = nil
        case .stamp(let kind):
            let swiftUIFrame = CGRect(x: value.location.x - 16, y: value.location.y - 16, width: 32, height: 32)
            annotations.append(AnnotationObject(
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
        default:
            guard let start = dragStart else { return }
            let swiftUIFrame = CGRect(
                x: min(start.x, value.location.x), y: min(start.y, value.location.y),
                width: abs(value.location.x - start.x), height: abs(value.location.y - start.y)
            )
            dragStart = nil
            guard swiftUIFrame.width > 2, swiftUIFrame.height > 2 else { return }
            let kind: AnnotationKind = selectedTool == .arrow ? .arrow : (selectedTool == .highlighter ? .highlighter : (selectedTool == .blur ? .blur : .rectangle))
            annotations.append(AnnotationObject(
                id: UUID(), kind: kind,
                frame: rendererFrame(fromSwiftUIFrame: swiftUIFrame),
                color: currentColor, strokeWidth: currentStrokeWidth
            ))
        }
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
    /// - `.arrow`: the two renderer-space corners `AnnotationRenderer.drawArrow` itself draws
    ///   between (`(frame.minX, frame.minY)` -> `(frame.maxX, frame.maxY)`), converted so the
    ///   live preview's arrow direction matches what the final flattened render will show.
    /// - everything else: unused by the shape, so empty.
    private func displayPoints(for annotation: AnnotationObject) -> [CGPoint] {
        switch annotation.kind {
        case .freehand(let points):
            return points.map { swiftUIPoint(fromRendererPoint: $0) }
        case .arrow:
            let rendererStart = CGPoint(x: annotation.frame.minX, y: annotation.frame.minY)
            let rendererEnd = CGPoint(x: annotation.frame.maxX, y: annotation.frame.maxY)
            return [swiftUIPoint(fromRendererPoint: rendererStart), swiftUIPoint(fromRendererPoint: rendererEnd)]
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
    }

    @ViewBuilder
    private var content: some View {
        switch annotation.kind {
        case .rectangle:
            Rectangle()
                .stroke(color, lineWidth: annotation.strokeWidth)
                .frame(width: displayFrame.width, height: displayFrame.height)
                .position(x: displayFrame.midX, y: displayFrame.midY)
        case .arrow:
            if displayPoints.count == 2 {
                arrowPath(from: displayPoints[0], to: displayPoints[1])
                    .stroke(color, lineWidth: annotation.strokeWidth)
            }
        case .freehand:
            freehandPath
                .stroke(color, style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round, lineJoin: .round))
        case .text(let string):
            Text(string)
                .font(.system(size: max(displayFrame.height * 0.7, 10)))
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

    private func arrowPath(from start: CGPoint, to end: CGPoint) -> Path {
        Path { path in
            path.move(to: start)
            path.addLine(to: end)

            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLength: CGFloat = 10
            let p1 = CGPoint(x: end.x - headLength * cos(angle - .pi / 6), y: end.y - headLength * sin(angle - .pi / 6))
            let p2 = CGPoint(x: end.x - headLength * cos(angle + .pi / 6), y: end.y - headLength * sin(angle + .pi / 6))
            path.move(to: end)
            path.addLine(to: p1)
            path.move(to: end)
            path.addLine(to: p2)
        }
    }
}
