import CoreGraphics
import Foundation

/// Builds the click marker and cursor trail as ordinary annotations, so they open in the editor
/// as editable shapes rather than being burned into the step's pixels.
enum StepAnnotationFactory {
    static let ringDiameter: CGFloat = 36
    static let ringStroke: CGFloat = 3
    static let dotDiameter: CGFloat = 14
    static let trailStroke: CGFloat = 2
    static let trailAlpha: CGFloat = 0.6

    /// The editor's default colour, so a marker looks like something the user could have drawn.
    static var markerColor: RGBAColor { EditorView.swatchColors[5] }

    static func marker(at imagePoint: CGPoint, style: AdvancedModeSettings.MarkerStyle, imageSize: CGSize) -> AnnotationObject {
        let center = StepGeometry.toRenderer(imagePoint, imageHeight: imageSize.height)
        let diameter = style == .ring ? ringDiameter : dotDiameter
        // A dot is an ellipse stroked as thick as its radius, which fills it without needing a
        // new filled-shape annotation kind.
        let stroke = style == .ring ? ringStroke : dotDiameter / 2
        return AnnotationObject(
            id: UUID(), kind: .ellipse,
            frame: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter),
            color: markerColor, strokeWidth: stroke
        )
    }

    static func trail(globalPoints: [CGPoint], captureOrigin: CGPoint, imageSize: CGSize) -> AnnotationObject? {
        let points = globalPoints
            .compactMap { StepGeometry.imagePoint(global: $0, captureOrigin: captureOrigin, imageSize: imageSize) }
            .map { StepGeometry.toRenderer($0, imageHeight: imageSize.height) }
        guard points.count >= 2 else { return nil }
        var color = markerColor
        color.alpha = trailAlpha
        return AnnotationObject(id: UUID(), kind: .freehand(points), frame: boundingBox(points), color: color, strokeWidth: trailStroke)
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
