import XCTest
import Cocoa
@testable import Clipr

final class CaptureGeometryTests: XCTestCase {
    private func makeTestImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.set()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
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
        XCTAssertEqual(cropped?.size, NSSize(width: 10, height: 10))
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
