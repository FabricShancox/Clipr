import SwiftUI

/// Renders one annotation's live, in-progress appearance on the canvas (so the user sees what
/// they're drawing immediately, without waiting for `AnnotationRenderer.flatten` to run), plus
/// its selection outline on top. This is a lightweight SwiftUI approximation of what
/// `AnnotationRenderer` will eventually flatten onto the image — it does not need to be
/// pixel-identical to that final render, only visibly represent each annotation kind.
struct AnnotationOverlayShape: View {
    let annotation: AnnotationObject
    /// The capture being annotated. Needed only by `.blur`, which shows the actual pixelated
    /// pixels rather than a placeholder — for a redaction tool the preview has to be the truth,
    /// since the user decides from it whether something is really covered.
    let baseImage: NSImage
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

    private var color: Color { swiftUIColor(annotation.color) }

    private func swiftUIColor(_ rgba: RGBAColor) -> Color {
        Color(
            red: Double(rgba.red),
            green: Double(rgba.green),
            blue: Double(rgba.blue),
            opacity: Double(rgba.alpha)
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
            // Wraps at the frame's width and is never truncated: `fixedSize` lets text taller than
            // an old, un-grown box hang below it (matching the renderer) instead of ending in "…".
            // The border sits at `textBorderRect`, the same outset the export draws.
            Text(string)
                .font(styledSwiftUIFont(style))
                .foregroundColor(color)
                .multilineTextAlignment(swiftUITextAlignment(style.horizontalAlign))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: displayFrame.width, alignment: swiftUIFrameAlignment(horizontal: style.horizontalAlign, vertical: .top))
                .frame(
                    width: displayFrame.width, height: displayFrame.height,
                    alignment: swiftUIFrameAlignment(horizontal: style.horizontalAlign, vertical: style.verticalAlign)
                )
                .background(
                    style.border
                        ? RoundedRectangle(cornerRadius: 4)
                            .stroke(color, lineWidth: 1.5)
                            .padding(.horizontal, -textBorderInset.width)
                            .padding(.vertical, -textBorderInset.height)
                        : nil
                )
                .position(x: displayFrame.midX, y: displayFrame.midY)
        case .highlighter:
            Rectangle()
                .fill(color.opacity(0.35))
                .frame(width: displayFrame.width, height: displayFrame.height)
                .position(x: displayFrame.midX, y: displayFrame.midY)
        case .blur:
            redactionPreview
        case .stamp(let kind):
            if let number = kind.number {
                discStamp { Text("\(number)").font(.system(size: stampSide * StampKind.digitScale(for: number), weight: .bold, design: .rounded)) }
            } else if let glyph = kind.discGlyph {
                discStamp {
                    Image(systemName: glyph)
                        .font(.system(size: stampSide * StampKind.glyphScale, weight: .bold))
                }
            } else {
                Image(systemName: kind.symbolName)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(color)
                    .frame(width: displayFrame.width, height: displayFrame.height)
                    .position(x: displayFrame.midX, y: displayFrame.midY)
            }
        }
    }

    /// Disc diameter. `min` keeps it circular in a non-square frame, matching how `scaledToFit`
    /// centred the symbol for the stamp kinds still drawn from one.
    private var stampSide: CGFloat { min(displayFrame.width, displayFrame.height) }

    /// A solid disc with `mark` drawn on top in a contrasting colour, rather than an SF Symbol
    /// whose mark is a transparent cutout through the disc.
    private func discStamp<Mark: View>(@ViewBuilder mark: () -> Mark) -> some View {
        ZStack {
            Circle().fill(color)
            mark().foregroundColor(swiftUIColor(annotation.color.contrastingForeground))
        }
        .frame(width: stampSide, height: stampSide)
        .position(x: displayFrame.midX, y: displayFrame.midY)
    }

    /// The redacted region as it will actually be exported: the underlying pixels, pixelated.
    ///
    /// `displayFrame` is already in the image's own point space with a top-left origin — the
    /// canvas draws the capture 1:1 and applies zoom outside it — which is the convention
    /// `Pixelation` expects, once scaled to the bitmap's pixels. Falls back to an opaque box if the region
    /// can't be sampled; opaque rather than the old 90% so a failure can never leak the content
    /// it was meant to hide.
    @ViewBuilder
    private var redactionPreview: some View {
        if annotation.redactionStyle == .solid {
            Rectangle()
                .fill(Color(white: 0.12))
                .frame(width: displayFrame.width, height: displayFrame.height)
                .position(x: displayFrame.midX, y: displayFrame.midY)
        } else if let (pixelated, visible) = PixelatedPreviewCache.shared.preview(of: baseImage, in: displayFrame) {
            // Drawn over the on-canvas part only, matching the renderer: a redaction hanging off
            // the edge used to have its clipped region stretched across the whole frame.
            Image(decorative: pixelated, scale: 1)
                .resizable()
                .interpolation(.none)
                .frame(width: visible.width, height: visible.height)
                .position(x: visible.midX, y: visible.midY)
        } else {
            Rectangle()
                .fill(Color(white: 0.5))
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
