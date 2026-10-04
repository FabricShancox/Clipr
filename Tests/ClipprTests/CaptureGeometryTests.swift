import XCTest
import Cocoa
@testable import Clipr

final class CaptureGeometryTests: XCTestCase {
    private func makeTestImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let image = testImage(width: width, height: height) {
            color.set()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
        return image
    }

    // MARK: - Canvas resize bounds

    func testACornerDraggedFarOutwardIsHeldToFourTimesTheImage() {
        let corner = CaptureGeometry.clampedCanvasCorner(
            CGPoint(x: 100_000, y: -50_000), fixed: .zero, imageSize: CGSize(width: 800, height: 600), pixelScale: 1
        )
        XCTAssertEqual(corner, CGPoint(x: 3200, y: -2400))
    }

    func testTheCanvasNeverExceedsTheMaximumPixelSize() {
        let corner = CaptureGeometry.clampedCanvasCorner(
            CGPoint(x: 100_000, y: 100_000), fixed: CGPoint(x: 10, y: 10), imageSize: CGSize(width: 6000, height: 6000), pixelScale: 2
        )
        let width = (corner.x - 10) * 2, height = (corner.y - 10) * 2
        XCTAssertLessThanOrEqual(width, 16_384)
        XCTAssertLessThanOrEqual(height, 16_384)
        XCTAssertLessThanOrEqual(Int(width) * Int(height), DecodeLimits.maxImagePixels, "the result must reopen")
        XCTAssertEqual(width, height, accuracy: 1, "shrunk evenly")
        XCTAssertGreaterThan(Int(width) * Int(height), DecodeLimits.maxImagePixels - 40_000, "but no further than needed")
    }

    func testTheCanvasPixelCountStaysWithinTheDecodeLimitForAWideDrag() {
        // 16,384 × 15,000 is within the per-side limit but 245 MP in all.
        let corner = CaptureGeometry.clampedCanvasCorner(
            CGPoint(x: -16_384, y: 15_000), fixed: .zero, imageSize: CGSize(width: 6000, height: 6000), pixelScale: 1
        )
        XCTAssertLessThan(corner.x, 0, "direction kept")
        XCTAssertLessThanOrEqual(Int(-corner.x) * Int(corner.y), DecodeLimits.maxImagePixels)
        XCTAssertEqual(-corner.x / corner.y, 16_384 / 15_000, accuracy: 0.001)
    }

    func testAnOrdinaryDragIsUnchanged() {
        let point = CGPoint(x: 900, y: 700)
        XCTAssertEqual(CaptureGeometry.clampedCanvasCorner(point, fixed: .zero, imageSize: CGSize(width: 800, height: 600), pixelScale: 2), point)
    }

    // MARK: - rendererDelta

    func testRendererDeltaIsZeroForANoOpResize() {
        let delta = CaptureGeometry.rendererDelta(oldHeight: 100, newTopLeftOrigin: .zero, newSize: CGSize(width: 50, height: 100))
        XCTAssertEqual(delta, .zero)
    }

    func testRendererDeltaWhenTrimmingOnlyFromTheTop() {
        // Old height 100, keep bottom 80 (top-left origin y=20, new height 80): the bottom edge
        // is unchanged, so points near the old bottom shouldn't move at all.
        let delta = CaptureGeometry.rendererDelta(oldHeight: 100, newTopLeftOrigin: CGPoint(x: 0, y: 20), newSize: CGSize(width: 50, height: 80))
        XCTAssertEqual(delta, .zero)
    }

    func testRendererDeltaWhenTrimmingOnlyFromTheBottom() {
        // Old height 100, keep top 80 (origin unchanged, new height 80): a point 5 units below
        // the old top (renderer-y 95) should land at renderer-y 75 in the new, shorter canvas.
        let delta = CaptureGeometry.rendererDelta(oldHeight: 100, newTopLeftOrigin: .zero, newSize: CGSize(width: 50, height: 80))
        XCTAssertEqual(CGPoint(x: 0, y: 95 + delta.y), CGPoint(x: 0, y: 75))
    }

    // MARK: - remapAnnotations

    private func annotation(frame: CGRect) -> AnnotationObject {
        AnnotationObject(id: UUID(), kind: .rectangle, frame: frame, color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 1), strokeWidth: 1)
    }

    func testRemapAnnotationsTranslatesFrameByDelta() {
        let original = annotation(frame: CGRect(x: 10, y: 10, width: 20, height: 20))
        let remapped = CaptureGeometry.remapAnnotations([original], delta: CGPoint(x: -5, y: 5), newSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(remapped.first?.frame, CGRect(x: 5, y: 15, width: 20, height: 20))
    }

    func testRemapAnnotationsDropsOnesEntirelyOutsideTheNewCanvas() {
        let farAway = annotation(frame: CGRect(x: 1000, y: 1000, width: 10, height: 10))
        let remapped = CaptureGeometry.remapAnnotations([farAway], delta: .zero, newSize: CGSize(width: 100, height: 100))
        XCTAssertTrue(remapped.isEmpty)
    }

    func testRemapAnnotationsKeepsOnesPartiallyOverlappingTheNewCanvas() {
        let partiallyIn = annotation(frame: CGRect(x: 90, y: 90, width: 20, height: 20))
        let remapped = CaptureGeometry.remapAnnotations([partiallyIn], delta: .zero, newSize: CGSize(width: 100, height: 100))
        XCTAssertEqual(remapped.count, 1)
    }

    // MARK: - cropped

    func testCroppedProducesAnImageOfTheRequestedSize() {
        let image = makeTestImage(width: 20, height: 20, color: .red)
        let cropped = CaptureGeometry.cropped(image, to: CGRect(x: 5, y: 5, width: 10, height: 10))
        XCTAssertEqual(cropped?.image.size, NSSize(width: 10, height: 10))
        XCTAssertEqual(cropped?.rect, CGRect(x: 5, y: 5, width: 10, height: 10))
    }

    /// A crop drag can carry on past the canvas edge. The returned image must match the pixels
    /// that actually exist rather than being stretched to the requested size, and the reported
    /// rect must be the clamped one so the caller remaps annotations against the real canvas.
    func testCroppedClampsARectThatRunsPastTheImageEdge() {
        let image = makeTestImage(width: 20, height: 20, color: .red)
        let cropped = CaptureGeometry.cropped(image, to: CGRect(x: 10, y: 10, width: 40, height: 40))

        XCTAssertEqual(cropped?.rect, CGRect(x: 10, y: 10, width: 10, height: 10))
        XCTAssertEqual(cropped?.image.size, NSSize(width: 10, height: 10), "must not stretch to the requested 40x40")
    }

    func testCroppedIntegralizesAFractionalRect() {
        let image = makeTestImage(width: 20, height: 20, color: .red)
        let cropped = CaptureGeometry.cropped(image, to: CGRect(x: 4.3, y: 4.6, width: 10.2, height: 10.4))

        let rect = try? XCTUnwrap(cropped?.rect)
        XCTAssertEqual(rect?.width, rect.map { CGFloat(Int($0.width)) }, "rect should be whole pixels")
        XCTAssertEqual(cropped?.image.size.width, cropped?.rect.width, "image and rect must agree")
        XCTAssertEqual(cropped?.image.size.height, cropped?.rect.height)
    }

    func testCroppedReturnsNilForARectFullyOutsideTheImage() {
        let image = makeTestImage(width: 20, height: 20, color: .red)
        XCTAssertNil(CaptureGeometry.cropped(image, to: CGRect(x: 50, y: 50, width: 10, height: 10)))
    }

    // MARK: - resizedCanvas

    func testResizedCanvasExpandLeavesNewAreaTransparent() {
        let image = makeTestImage(width: 10, height: 10, color: .red)
        // Expand to the right: new canvas is 20 wide, old image drawn at its original offset.
        let delta = CaptureGeometry.rendererDelta(oldHeight: 10, newTopLeftOrigin: .zero, newSize: CGSize(width: 20, height: 10))
        guard let resized = CaptureGeometry.resizedCanvas(image, to: CGRect(x: 0, y: 0, width: 20, height: 10), delta: delta),
              let cgImage = resized.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            XCTFail("expected a resized image")
            return
        }
        XCTAssertEqual(cgImage.width, 20)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        // Original content should still be opaque red near the left edge.
        XCTAssertGreaterThan(bitmap.colorAt(x: 1, y: 5)?.alphaComponent ?? 0, 0.9)
        // The newly-added area on the right should be transparent, not stretched/tiled content.
        XCTAssertEqual(bitmap.colorAt(x: 18, y: 5)?.alphaComponent ?? 1, 0, accuracy: 0.01)
    }

    func testResizedCanvasShrinkBehavesAsAnOrdinaryCrop() {
        let image = makeTestImage(width: 20, height: 20, color: .red)
        let topLeftRect = CGRect(x: 0, y: 0, width: 10, height: 20)
        let delta = CaptureGeometry.rendererDelta(oldHeight: 20, newTopLeftOrigin: topLeftRect.origin, newSize: topLeftRect.size)
        let resized = CaptureGeometry.resizedCanvas(image, to: topLeftRect, delta: delta)
        XCTAssertEqual(resized?.size, NSSize(width: 10, height: 20))
    }
}
