import CoreGraphics
import Foundation

/// Builds the click marker and cursor trail as ordinary annotations, so they open in the editor
/// as editable shapes rather than being burned into the step's pixels.
enum StepAnnotationFactory {
    static let ringDiameter: CGFloat = 36
    static let ringStroke: CGFloat = 3
    static let trailStroke: CGFloat = 2.5
    static let trailAlpha: CGFloat = 0.5

    /// The editor's default colour, so a marker looks like something the user could have drawn.
    static var markerColor: RGBAColor { EditorView.swatchColors[5] }

    static func marker(at imagePoint: CGPoint, style: AdvancedModeSettings.MarkerStyle, imageSize: CGSize) -> AnnotationObject {
        let center = StepGeometry.toRenderer(imagePoint, imageHeight: imageSize.height)

        if style == .ring {
            return AnnotationObject(
                id: UUID(), kind: .ellipse,
                frame: CGRect(x: center.x - ringDiameter / 2, y: center.y - ringDiameter / 2, width: ringDiameter, height: ringDiameter),
                color: markerColor, strokeWidth: ringStroke
            )
        } else {
            // A dot: frame is 7×7 (half the visual diameter), stroked at 7pt so the stroke extends
            // 3.5pt inward and outward from the 3.5pt radius path, filling a solid 14pt circle.
            let dotFrame = CGFloat(7)
            return AnnotationObject(
                id: UUID(), kind: .ellipse,
                frame: CGRect(x: center.x - dotFrame / 2, y: center.y - dotFrame / 2, width: dotFrame, height: dotFrame),
                color: markerColor, strokeWidth: dotFrame
            )
        }
    }

    /// How much of the cursor's path to keep, measured back from the click. The whole path since
    /// the previous step wanders across the screen and reads as a scribble; the last stretch is the
    /// part that actually says "the pointer came from here".
    static let trailMaxLength: CGFloat = 240
    /// Shorter than this and the trail is just a smudge under the marker.
    static let trailMinLength: CGFloat = 24

    static func trail(globalPoints: [CGPoint], captureOrigin: CGPoint, imageSize: CGSize) -> AnnotationObject? {
        // Only the final unbroken run inside the image: dropping off-image points and joining what's
        // left draws straight chords across the step wherever the pointer left the window.
        var run: [CGPoint] = []
        for global in globalPoints.reversed() {
            guard let point = StepGeometry.imagePoint(global: global, captureOrigin: captureOrigin, imageSize: imageSize) else { break }
            run.append(point)
        }
        run.reverse()
        let approach = lastStretch(of: run, maxLength: trailMaxLength)
        guard approach.count >= 2, pathLength(approach) >= trailMinLength else { return nil }
        let points = smoothed(approach).map { StepGeometry.toRenderer($0, imageHeight: imageSize.height) }
        var color = markerColor
        color.alpha = trailAlpha
        return AnnotationObject(id: UUID(), kind: .freehand(points), frame: boundingBox(points), color: color, strokeWidth: trailStroke)
    }

    /// The tail of `points` whose path length is at most `maxLength`, cutting the first segment
    /// part-way so the trail is exactly that long rather than jumping to the next sample.
    static func lastStretch(of points: [CGPoint], maxLength: CGFloat) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        var kept = [points[points.count - 1]]
        var remaining = maxLength
        for index in stride(from: points.count - 2, through: 0, by: -1) {
            let from = kept[kept.count - 1], to = points[index]
            let length = hypot(to.x - from.x, to.y - from.y)
            if length >= remaining {
                let t = length > 0 ? remaining / length : 0
                kept.append(CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
                break
            }
            kept.append(to)
            remaining -= length
        }
        return kept.reversed()
    }

    static func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    /// Chaikin corner-cutting, keeping both endpoints so the trail still ends exactly on the click.
    /// Mouse samples are a jagged polyline; two passes round them into a natural-looking curve.
    static func smoothed(_ points: [CGPoint], passes: Int = 2) -> [CGPoint] {
        var result = points
        for _ in 0..<passes where result.count > 2 {
            var next = [result[0]]
            for (a, b) in zip(result, result.dropFirst()) {
                next.append(CGPoint(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y))
                next.append(CGPoint(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y))
            }
            next.append(result[result.count - 1])
            result = next
        }
        return result
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
