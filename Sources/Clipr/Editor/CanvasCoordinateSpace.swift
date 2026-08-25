import CoreGraphics

/// Conversions between SwiftUI's y-down space (as reported by `DragGesture`, origin top-left)
/// and the y-up-from-bottom "renderer space" `AnnotationObject.frame` uses (matching
/// `AnnotationRenderer`'s unflipped `CGContext`, empirically verified against CGContext's native
/// bottom-left-origin convention). `canvasHeight` is the canvas's point height — since
/// `AnnotationCanvasView` renders at 1:1 with the base image, that's `image.size.height`.
///
/// Both the rect and point conversions use the same formula in both directions
/// (`y' = canvasHeight - y - height` for rects, `y' = canvasHeight - y` for bare points), because
/// that formula is its own inverse — kept as separately-named functions at each call site so the
/// direction of a given conversion stays unambiguous to read.

/// Converts a rect from SwiftUI's y-down space into renderer space.
func rendererFrame(fromSwiftUIFrame swiftUIFrame: CGRect, canvasHeight: CGFloat) -> CGRect {
    CGRect(
        x: swiftUIFrame.origin.x,
        y: canvasHeight - swiftUIFrame.origin.y - swiftUIFrame.height,
        width: swiftUIFrame.width,
        height: swiftUIFrame.height
    )
}

/// Converts a stored renderer-space frame back into SwiftUI's y-down space for on-screen display.
func swiftUIFrame(fromRendererFrame rendererFrame: CGRect, canvasHeight: CGFloat) -> CGRect {
    CGRect(
        x: rendererFrame.origin.x,
        y: canvasHeight - rendererFrame.origin.y - rendererFrame.height,
        width: rendererFrame.width,
        height: rendererFrame.height
    )
}

/// Converts a single point from SwiftUI's y-down space into renderer y-up space.
func rendererPoint(fromSwiftUIPoint point: CGPoint, canvasHeight: CGFloat) -> CGPoint {
    CGPoint(x: point.x, y: canvasHeight - point.y)
}

/// Converts a single point from renderer y-up space back into SwiftUI's y-down display space.
func swiftUIPoint(fromRendererPoint point: CGPoint, canvasHeight: CGFloat) -> CGPoint {
    CGPoint(x: point.x, y: canvasHeight - point.y)
}
