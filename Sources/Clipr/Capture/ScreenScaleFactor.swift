import Cocoa

/// `windowInfo.bounds` lives in the CG "global display" points space that
/// `CaptureOverlayView.globalDisplayPoint`/`viewLocalPoint` document and convert to/from (origin
/// at the top-left of the main display, y increasing downward) - the same space `kCGWindowBounds`
/// uses. To find the `backingScaleFactor` of the screen a window is actually on, each candidate
/// `NSScreen`'s frame is converted into that same space (by reusing
/// `CaptureOverlayView.globalDisplayPoint` on that screen's own local origin, `.zero`, which
/// yields the screen's top-left corner in global-display coordinates), rather than comparing
/// `windowInfo.bounds` directly against `NSScreen.frame` (a different, Cocoa-native,
/// bottom-left-origin/y-up space).
func screenScaleFactor(for windowBounds: CGRect) -> CGFloat {
    let screens = NSScreen.screens.map { screen -> (rect: CGRect, scale: CGFloat) in
        let topLeft = CaptureOverlayView.globalDisplayPoint(forViewLocalPoint: .zero, on: screen)
        return (CGRect(origin: topLeft, size: screen.frame.size), screen.backingScaleFactor)
    }
    return scaleFactor(for: windowBounds, screens: screens, fallback: NSScreen.main?.backingScaleFactor ?? 1.0)
}

/// The scale of the screen holding the largest part of `bounds`.
///
/// Not the screen containing the window's top-left corner: a window whose corner is off-screen,
/// or that starts on a 1x display but sits mostly on a 2x one, then fell back to the wrong scale
/// and came out blurry or oversized.
func scaleFactor(for bounds: CGRect, screens: [(rect: CGRect, scale: CGFloat)], fallback: CGFloat) -> CGFloat {
    var best: (area: CGFloat, scale: CGFloat)?
    for screen in screens {
        let overlap = screen.rect.intersection(bounds)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
        let area = overlap.width * overlap.height
        if area > (best?.area ?? 0) { best = (area, screen.scale) }
    }
    return best?.scale ?? fallback
}
