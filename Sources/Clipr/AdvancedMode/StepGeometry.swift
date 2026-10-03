import CoreGraphics

/// Coordinate conversions between where things happen on screen and where they belong in a
/// step image. Step images are sized in points (see `NSImage+PixelScale.swift`), so no pixel
/// scale appears here — only origins and the y-axis flip.
enum StepGeometry {
    /// `global` and `captureOrigin` are Quartz global points (top-left origin, y down). Returns the
    /// point inside the image (top-left origin), or `nil` if it falls outside it.
    static func imagePoint(global: CGPoint, captureOrigin: CGPoint, imageSize: CGSize) -> CGPoint? {
        let p = CGPoint(x: global.x - captureOrigin.x, y: global.y - captureOrigin.y)
        guard p.x >= 0, p.y >= 0, p.x < imageSize.width, p.y < imageSize.height else { return nil }
        return p
    }

    /// `AnnotationObject` geometry is bottom-left origin, y up (see `AnnotationRenderer.flatten`).
    static func toRenderer(_ p: CGPoint, imageHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: imageHeight - p.y)
    }

    /// An `NSScreen.frame` (AppKit space) as a Quartz global rect.
    static func globalTopLeftFrame(ofScreenFrame frame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryScreenHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// A rect from `CaptureOverlayView` (view-local points, top-left, view filling `screenFrame`)
    /// as a Quartz global rect.
    static func globalTopLeftRect(viewLocal rect: CGRect, screenFrame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let screen = globalTopLeftFrame(ofScreenFrame: screenFrame, primaryScreenHeight: primaryScreenHeight)
        return rect.offsetBy(dx: screen.minX, dy: screen.minY)
    }
}
