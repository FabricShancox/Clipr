import Cocoa

/// `windowInfo.bounds` lives in the CG "global display" points space that
/// `CaptureOverlayView.globalDisplayPoint`/`viewLocalPoint` document and convert to/from (origin
/// at the top-left of the main display, y increasing downward) - the same space `kCGWindowBounds`
/// uses. To find the `backingScaleFactor` of the screen a window is actually on, each candidate
/// `NSScreen`'s frame is converted into that same space (by reusing
/// `CaptureOverlayView.globalDisplayPoint` on that screen's own local origin, `.zero`, which
/// yields the screen's top-left corner in global-display coordinates) and tested for containment
/// against the window's origin, rather than comparing `windowInfo.bounds` directly against
/// `NSScreen.frame` (a different, Cocoa-native, bottom-left-origin/y-up space).
func screenScaleFactor(containing globalDisplayPoint: CGPoint) -> CGFloat {
    for screen in NSScreen.screens {
        let topLeft = CaptureOverlayView.globalDisplayPoint(forViewLocalPoint: .zero, on: screen)
        let screenRectInGlobalDisplaySpace = CGRect(origin: topLeft, size: screen.frame.size)
        if screenRectInGlobalDisplaySpace.contains(globalDisplayPoint) {
            return screen.backingScaleFactor
        }
    }
    return NSScreen.main?.backingScaleFactor ?? 1.0
}
