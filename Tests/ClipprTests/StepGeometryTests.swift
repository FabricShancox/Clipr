import XCTest
@testable import Clipr

final class StepGeometryTests: XCTestCase {
    func testOffsetWindow() {
        let p = StepGeometry.imagePoint(global: CGPoint(x: 150, y: 260), captureOrigin: CGPoint(x: 100, y: 200),
                                        imageSize: CGSize(width: 400, height: 300))
        XCTAssertEqual(p, CGPoint(x: 50, y: 60))
    }

    func testNegativeOriginSecondaryDisplay() {
        // Display to the left of and above the primary: global coordinates are negative.
        let p = StepGeometry.imagePoint(global: CGPoint(x: -1500, y: -100), captureOrigin: CGPoint(x: -1920, y: -300),
                                        imageSize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(p, CGPoint(x: 420, y: 200))
    }

    func testOutsideImageIsNil() {
        let size = CGSize(width: 100, height: 100)
        XCTAssertNil(StepGeometry.imagePoint(global: CGPoint(x: 99, y: 250), captureOrigin: .zero, imageSize: size))
        XCTAssertNil(StepGeometry.imagePoint(global: CGPoint(x: -1, y: 5), captureOrigin: .zero, imageSize: size))
        XCTAssertNil(StepGeometry.imagePoint(global: CGPoint(x: 100, y: 5), captureOrigin: .zero, imageSize: size))
    }

    func testToRendererFlipsY() {
        XCTAssertEqual(StepGeometry.toRenderer(CGPoint(x: 10, y: 30), imageHeight: 100), CGPoint(x: 10, y: 70))
    }

    func testScreenFrameConversion() {
        // Primary 1000 tall. A display above the primary in AppKit space (y 1000...1600).
        let frame = CGRect(x: 0, y: 1000, width: 800, height: 600)
        XCTAssertEqual(StepGeometry.globalTopLeftFrame(ofScreenFrame: frame, primaryScreenHeight: 1000),
                       CGRect(x: 0, y: -600, width: 800, height: 600))
    }

    func testViewLocalRectConversion() {
        let screen = CGRect(x: 1440, y: 0, width: 1000, height: 800)
        let r = StepGeometry.globalTopLeftRect(viewLocal: CGRect(x: 10, y: 20, width: 30, height: 40),
                                               screenFrame: screen, primaryScreenHeight: 900)
        XCTAssertEqual(r, CGRect(x: 1450, y: 120, width: 30, height: 40))
    }

    /// The spec requires proving a saved Retina step reloads in the point space markers are
    /// computed in — otherwise every marker on a 2x display lands at half/double position.
    func testRetinaStepReloadsInPointSpace() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storage = StorageManager(baseFolder: folder)
        let image = testImage(width: 200, height: 100, scale: 2) {
            NSColor.blue.set(); NSRect(x: 0, y: 0, width: 200, height: 100).fill()
        }
        let url = try storage.saveStep(image, index: 1, in: folder)
        let reloaded = try XCTUnwrap(NSImage(contentsOf: url))
        XCTAssertEqual(reloaded.size, CGSize(width: 200, height: 100))
        XCTAssertEqual(reloaded.pixelScale, 2)
    }
}
