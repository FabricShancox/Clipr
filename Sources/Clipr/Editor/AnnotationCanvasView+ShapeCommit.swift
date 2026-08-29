import SwiftUI

/// Per-kind annotation creation, called from `AnnotationCanvasView+Gestures.swift`'s
/// `handleDragEnded` dispatch. See `AnnotationCanvasView.swift`'s header for how this file
/// relates to the rest of the type.
extension AnnotationCanvasView {
    func commitFreehand() {
        dragStart = nil
        guard !freehandPoints.isEmpty else { return }
        let rendererPoints = freehandPoints.map { rendererPoint(fromSwiftUIPoint: $0, canvasHeight: canvasHeight) }
        commit(AnnotationObject(
            id: UUID(), kind: .freehand(rendererPoints),
            frame: boundingBox(of: rendererPoints),
            color: currentColor, strokeWidth: currentStrokeWidth
        ))
        freehandPoints = []
    }

    func commitText(endingAt location: CGPoint) {
        let start = dragStart ?? location
        let dragged = rectBetween(start, location)
        // A real drag sizes the box; a plain click (or a drag too small to have been
        // deliberate) falls back to a sensible default sized to the current font, so
        // click-to-place still works.
        let minHeight = currentTextStyle.fontSize + 10
        let swiftUIFrame = dragged.width >= 24 && dragged.height >= 16
            ? CGRect(x: dragged.origin.x, y: dragged.origin.y, width: dragged.width, height: max(dragged.height, minHeight))
            : CGRect(x: start.x, y: start.y, width: 160, height: minHeight)
        let newAnnotation = AnnotationObject(
            id: UUID(), kind: .text("", currentTextStyle),
            frame: rendererFrame(fromSwiftUIFrame: swiftUIFrame, canvasHeight: canvasHeight),
            color: currentColor, strokeWidth: currentStrokeWidth
        )
        commit(newAnnotation)
        editingTextID = newAnnotation.id
        dragStart = nil
        dragCurrentLocation = nil
    }

    func commitStamp(_ kind: StampKind, at location: CGPoint) {
        let swiftUIFrame = CGRect(x: location.x - 16, y: location.y - 16, width: 32, height: 32)
        commit(AnnotationObject(
            id: UUID(), kind: .stamp(kind),
            frame: rendererFrame(fromSwiftUIFrame: swiftUIFrame, canvasHeight: canvasHeight),
            color: currentColor, strokeWidth: currentStrokeWidth
        ))
        dragStart = nil
        dragCurrentLocation = nil
    }

    func commitArrow(endingAt location: CGPoint) {
        guard let start = dragStart else { return }
        let rendererStart = rendererPoint(fromSwiftUIPoint: start, canvasHeight: canvasHeight)
        let rendererEnd = rendererPoint(fromSwiftUIPoint: location, canvasHeight: canvasHeight)
        dragStart = nil
        dragCurrentLocation = nil
        guard hypot(location.x - start.x, location.y - start.y) > 2 else { return }
        commit(AnnotationObject(
            id: UUID(), kind: .arrow(rendererStart, rendererEnd),
            frame: boundingBox(of: [rendererStart, rendererEnd]),
            color: currentColor, strokeWidth: currentStrokeWidth
        ))
    }

    func commitCrop(endingAt location: CGPoint) {
        guard let start = dragStart else { return }
        let swiftUIFrame = rectBetween(start, location)
        dragStart = nil
        dragCurrentLocation = nil
        guard swiftUIFrame.width > 4, swiftUIFrame.height > 4 else { return }
        onCropRequested?(rendererFrame(fromSwiftUIFrame: swiftUIFrame, canvasHeight: canvasHeight))
    }

    func commitPlainShape(endingAt location: CGPoint) {
        guard let start = dragStart else { return }
        let swiftUIFrame = rectBetween(start, location)
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
            frame: rendererFrame(fromSwiftUIFrame: swiftUIFrame, canvasHeight: canvasHeight),
            color: currentColor, strokeWidth: currentStrokeWidth,
            // Recorded per annotation rather than read at render time, so changing the tool's
            // style later doesn't retroactively alter redactions already placed.
            redactionStyle: kind == .blur ? redactionStyle : nil
        ))
    }
}
