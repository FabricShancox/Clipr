import SwiftUI

/// What the user is actively drawing right now, before it commits into `annotations` on
/// drag-end. Drawn in raw SwiftUI-space coordinates (never stored, so no flip needed). See
/// `AnnotationCanvasView.swift`'s header for how this file relates to the rest of the type.
extension AnnotationCanvasView {
    @ViewBuilder
    var livePreview: some View {
        switch selectedTool {
        case .freehand:
            if !freehandPoints.isEmpty {
                livePath(freehandPoints)
                    .stroke(displayColor, style: StrokeStyle(lineWidth: currentStrokeWidth, lineCap: .round, lineJoin: .round))
            }
        case .arrow:
            if let start = dragStart, let current = dragCurrentLocation {
                ArrowView(start: start, end: current, strokeWidth: currentStrokeWidth, color: displayColor)
            }
        case .rectangle, .ellipse, .highlighter, .blur:
            if let start = dragStart, let current = dragCurrentLocation {
                liveShapePreview(for: selectedTool, in: rectBetween(start, current))
            }
        case .text:
            if let start = dragStart, let current = dragCurrentLocation {
                let rect = rectBetween(start, current)
                Rectangle()
                    .strokeBorder(displayColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
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

    @ViewBuilder
    func liveShapePreview(for tool: AnnotationTool, in rect: CGRect) -> some View {
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

    func livePath(_ points: [CGPoint]) -> Path {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }
}
