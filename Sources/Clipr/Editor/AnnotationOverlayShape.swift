import SwiftUI

/// Renders one annotation's live, in-progress appearance on the canvas (so the user sees what
/// they're drawing immediately, without waiting for `AnnotationRenderer.flatten` to run), plus
/// its selection outline on top. This is a lightweight SwiftUI approximation of what
/// `AnnotationRenderer` will eventually flatten onto the image — it does not need to be
/// pixel-identical to that final render, only visibly represent each annotation kind.
struct AnnotationOverlayShape: View {
    let annotation: AnnotationObject
    /// `annotation.frame` already converted into SwiftUI's y-down display space (or, while a
    /// resize drag is live, the in-progress resized frame — see the `ForEach` call site).
    let displayFrame: CGRect
    /// Extra points needed for `.freehand` (the full stroke, converted) and `.arrow` (the two
    /// endpoints, converted) — see `AnnotationCanvasView.displayPoints(for:)`. Empty for kinds
    /// that don't need it.
    let displayPoints: [CGPoint]
    let isSelected: Bool
    /// True while the mouse hovers this annotation with a non-Select drawing tool active — see
    /// `AnnotationCanvasView+Hover.swift`. Shown as a distinct (dashed, not solid) outline from
    /// `isSelected`'s, so "this is selectable" and "this is selected" read as different states.
    var isHovered: Bool = false
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
            hoverOutline
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
                ArrowView(start: displayPoints[0], end: displayPoints[1], strokeWidth: annotation.strokeWidth, color: color)
            }
        case .freehand:
            freehandPath
                .stroke(color, style: StrokeStyle(lineWidth: annotation.strokeWidth, lineCap: .round, lineJoin: .round))
        case .text(let string, let style):
            Text(string)
                .font(styledSwiftUIFont(style))
                .foregroundColor(color)
                .multilineTextAlignment(swiftUITextAlignment(style.horizontalAlign))
                .frame(
                    width: displayFrame.width, height: displayFrame.height,
                    alignment: swiftUIFrameAlignment(horizontal: style.horizontalAlign, vertical: style.verticalAlign)
                )
                .background(style.border ? RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 1.5) : nil)
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

    private var hoverOutline: some View {
        Rectangle()
            .stroke(
                isHovered && !isSelected ? Color.white.opacity(0.8) : Color.clear,
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
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
