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
/// annotation's frame for on-screen SwiftUI display (e.g. the selection outline). Both
/// conversions use the same formula, `y' = canvasHeight - y - height` for rects (or
/// `y' = canvasHeight - y` for bare points), because that formula is its own inverse.
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
                    displayFrame: swiftUIFrame(fromRendererFrame: annotation.frame),
                    isSelected: annotation.id == selectedID
                )
            }
        }
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
}

private struct AnnotationOverlayShape: View {
    /// Already converted into SwiftUI's y-down display space by the caller.
    let displayFrame: CGRect
    let isSelected: Bool

    var body: some View {
        Rectangle()
            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            .frame(width: displayFrame.width, height: displayFrame.height)
            .position(x: displayFrame.midX, y: displayFrame.midY)
    }
}
