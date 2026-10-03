import XCTest
import Cocoa
@testable import Clipr

/// Captures are point-sized with a 2x bitmap on Retina (see `NSImage+PixelScale.swift`). These
/// check that every operation on one keeps the full resolution and puts things where the points
/// say they go.
final class RetinaCaptureTests: XCTestCase {
    /// 100×60 points, 200×120 pixels: left half black, right half white.
    private func retinaImage() -> NSImage {
        testImage(width: 100, height: 60, scale: 2) {
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: 50, height: 60).fill()
            NSColor.white.setFill()
            NSRect(x: 50, y: 0, width: 50, height: 60).fill()
        }
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        NSBitmapImageRep(cgImage: try XCTUnwrap(image.bitmap))
    }

    func testPixelScaleIsTheBitmapDensity() {
        XCTAssertEqual(retinaImage().pixelScale, 2)
        XCTAssertEqual(testImage(width: 10, height: 10) {}.pixelScale, 1)
    }

    func testFlattenKeepsFullResolutionAndDrawsInPoints() throws {
        let box = AnnotationObject(
            id: UUID(), kind: .highlighter,
            // Renderer space (y up): the top-right 20×20 points.
            frame: CGRect(x: 80, y: 40, width: 20, height: 20),
            color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1), strokeWidth: 4
        )
        let flattened = AnnotationRenderer.flatten(base: retinaImage(), annotations: [box])
        XCTAssertEqual(flattened.size, NSSize(width: 100, height: 60))
        let out = try bitmap(flattened)
        XCTAssertEqual(out.pixelsWide, 200)
        XCTAssertEqual(out.pixelsHigh, 120)
        // Bitmap rows run top-down: pixel (190, 10) is inside the top-right highlight.
        let tinted = try XCTUnwrap(out.colorAt(x: 190, y: 10))
        XCTAssertGreaterThan(tinted.redComponent, tinted.blueComponent + 0.2)
        // And pixel (190, 110), bottom-right, is still plain white.
        XCTAssertEqual(try XCTUnwrap(out.colorAt(x: 190, y: 110)).brightnessComponent, 1, accuracy: 0.02)
    }

    func testRedactionCoversTheRightPixels() throws {
        // Over the black/white boundary, so pixelation has to blend the two.
        let redaction = AnnotationObject(
            id: UUID(), kind: .blur, frame: CGRect(x: 30, y: 0, width: 40, height: 60),
            color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 1), strokeWidth: 1
        )
        let out = try bitmap(AnnotationRenderer.flatten(base: retinaImage(), annotations: [redaction]))
        // Outside the redaction the halves are untouched.
        XCTAssertEqual(try XCTUnwrap(out.colorAt(x: 10, y: 60)).brightnessComponent, 0, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(out.colorAt(x: 190, y: 60)).brightnessComponent, 1, accuracy: 0.02)
    }

    func testCropKeepsFullResolution() throws {
        let result = try XCTUnwrap(CaptureGeometry.cropped(retinaImage(), to: CGRect(x: 40, y: 0, width: 20, height: 30)))
        XCTAssertEqual(result.image.size, NSSize(width: 20, height: 30))
        let out = try bitmap(result.image)
        XCTAssertEqual(out.pixelsWide, 40)
        XCTAssertEqual(out.pixelsHigh, 60)
        // Left half of the crop came from the black side, right half from the white side.
        XCTAssertEqual(try XCTUnwrap(out.colorAt(x: 5, y: 30)).brightnessComponent, 0, accuracy: 0.02)
        XCTAssertEqual(try XCTUnwrap(out.colorAt(x: 35, y: 30)).brightnessComponent, 1, accuracy: 0.02)
    }

    func testCanvasResizeKeepsFullResolution() throws {
        let image = retinaImage()
        let rect = CGRect(x: 0, y: 0, width: 120, height: 60)
        let delta = CaptureGeometry.rendererDelta(oldHeight: 60, newTopLeftOrigin: .zero, newSize: rect.size)
        let resized = try XCTUnwrap(CaptureGeometry.resizedCanvas(image, to: rect, delta: delta))
        XCTAssertEqual(resized.size, NSSize(width: 120, height: 60))
        XCTAssertEqual(try bitmap(resized).pixelsWide, 240)
    }

    func testSavedCaptureReopensAtPointSizeWithEveryPixel() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = StorageManager(baseFolder: folder)
        let url = try storage.saveRawCapture(retinaImage(), date: Date())
        let reopened = try XCTUnwrap(NSImage(contentsOf: url))
        XCTAssertEqual(reopened.size, NSSize(width: 100, height: 60))
        XCTAssertEqual(reopened.pixelScale, 2)
    }

    func testBorderAndShadowKeepFullResolution() throws {
        let styled = AnnotationRenderer.applying(CopyStyle(border: true, shadow: true), to: retinaImage())
        XCTAssertEqual(styled.pixelScale, 2, accuracy: 0.05)
    }
}
