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

    /// The screen (of `screens`, Quartz global frames) a typing step in Screen scope shoots: the
    /// one showing most of the focused `field`, so a field whose midpoint is off every screen (half
    /// dragged off an edge, or straddling two displays) still lands somewhere. With no overlap at
    /// all, the first of `fallbacks` (the last click, then the pointer) that's on a screen.
    static func screenFrame(forField field: CGRect?, screens: [CGRect], fallbacks: [CGPoint?]) -> CGRect? {
        if let field {
            let best = screens
                .map { (frame: $0, area: area(of: $0.intersection(field))) }
                .filter { $0.area > 0 }
                .max { $0.area < $1.area }
            if let best { return best.frame }
        }
        for case let point? in fallbacks {
            if let screen = screens.first(where: { $0.contains(point) }) { return screen }
        }
        return nil
    }

    /// A point on the display `screenFrame(forField:…)` picks: the middle of the field's part on
    /// it, or the display's middle when the choice came from a fallback.
    static func typingCapturePoint(forField field: CGRect?, screens: [CGRect], fallbacks: [CGPoint?]) -> CGPoint? {
        guard let screen = screenFrame(forField: field, screens: screens, fallbacks: fallbacks) else { return nil }
        let visible = field.map { $0.intersection(screen) } ?? .null
        let region = area(of: visible) > 0 ? visible : screen
        return CGPoint(x: region.midX, y: region.midY)
    }

    private static func area(of rect: CGRect) -> CGFloat {
        rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
    }
}
