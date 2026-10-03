import XCTest
@testable import Clipr

final class StepZoomTests: XCTestCase {
    func testCenteredWhenRoomAllowsIt() {
        XCTAssertEqual(StepZoom.cropRect(centeredOn: CGPoint(x: 500, y: 400), imageSize: CGSize(width: 1000, height: 800)),
                       CGRect(x: 300, y: 250, width: 400, height: 300))
    }

    func testShiftedNotShrunkAtEdges() {
        let size = CGSize(width: 1000, height: 800)
        XCTAssertEqual(StepZoom.cropRect(centeredOn: CGPoint(x: 10, y: 10), imageSize: size),
                       CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(StepZoom.cropRect(centeredOn: CGPoint(x: 990, y: 790), imageSize: size),
                       CGRect(x: 600, y: 500, width: 400, height: 300))
    }

    func testSmallImageUsesWholeDimension() {
        XCTAssertEqual(StepZoom.cropRect(centeredOn: CGPoint(x: 100, y: 50), imageSize: CGSize(width: 300, height: 120)),
                       CGRect(x: 0, y: 0, width: 300, height: 120))
    }

    func testFractionalClickPointsAreRounded() {
        let rect = StepZoom.cropRect(centeredOn: CGPoint(x: 500.5, y: 400.5), imageSize: CGSize(width: 1000, height: 800))
        XCTAssertEqual(rect.width, 400)
        XCTAssertEqual(rect.height, 300)
        // Origin should be rounded (500.5 - 200 = 300.5 → 300 or 301)
        XCTAssertTrue(rect.origin.x.truncatingRemainder(dividingBy: 1) == 0, "x origin should be integer")
        XCTAssertTrue(rect.origin.y.truncatingRemainder(dividingBy: 1) == 0, "y origin should be integer")
    }

    func testCropKeepsRetinaPixelsAndSavesNextToStep() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = testImage(width: 1000, height: 800, scale: 2) { NSColor.green.set(); NSRect(x: 0, y: 0, width: 1000, height: 800).fill() }
        let zoom = try XCTUnwrap(StepZoom.image(from: image, centeredOn: CGPoint(x: 500, y: 400)))
        XCTAssertEqual(zoom.size, CGSize(width: 400, height: 300))
        XCTAssertEqual(zoom.pixelScale, 2)
        let storage = StorageManager(baseFolder: folder)
        let step = try storage.saveStep(image, index: 3, in: folder)
        let url = try storage.saveStepZoom(zoom, stepURL: step)
        XCTAssertEqual(url.lastPathComponent, "Step_03_zoom.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
