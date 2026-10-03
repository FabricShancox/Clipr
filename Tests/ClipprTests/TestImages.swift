import Cocoa
@testable import Clipr

/// A test image of exactly `scale` pixels per point, drawn with the usual AppKit calls.
///
/// `NSImage.lockFocus()` sizes its bitmap by the main screen — 2x on a Retina Mac, 1x on a CI
/// runner — and the renderer now keeps whatever resolution the base image has, so pixel-position
/// assertions need an image whose density doesn't depend on the machine running the tests.
func testImage(width: Int, height: Int, scale: CGFloat = 1, _ draw: () -> Void) -> NSImage {
    let size = CGSize(width: width, height: height)
    guard let context = NSImage.pixelContext(size: size, scale: scale) else { return NSImage(size: size) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    guard let cg = context.makeImage() else { return NSImage(size: size) }
    return NSImage(cgImage: cg, size: size)
}
