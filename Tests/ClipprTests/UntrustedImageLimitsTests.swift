import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import Clipr

// Security #9: images and sidecars from a session folder are size-checked before decoding.
final class UntrustedImageLimitsTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    /// A real PNG `width` × `height` pixels (cheap when one side is 1).
    private func png(_ name: String, width: Int, height: Int) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let url = folder.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    func testLimits() {
        XCTAssertTrue(UntrustedImageLimits.allows(width: 6016, height: 3384))
        XCTAssertFalse(UntrustedImageLimits.allows(width: 16_385, height: 1))
        XCTAssertFalse(UntrustedImageLimits.allows(width: 15_000, height: 15_000))
        XCTAssertFalse(UntrustedImageLimits.allows(width: 0, height: 10))
    }

    func testOversizedStepIsNotExported() throws {
        let url = try png("Step_01.png", width: 16_385, height: 1)
        XCTAssertFalse(UntrustedImageLimits.isSafeToDecode(url))
        XCTAssertNil(GuideImages.render(.file(url), maxPixelWidth: 800).image)
        XCTAssertNil(StepFiles.replacementPNG(from: url))
    }

    func testNormalStepStillExports() throws {
        let url = try png("Step_01.png", width: 40, height: 30)
        XCTAssertTrue(UntrustedImageLimits.isSafeToDecode(url))
        XCTAssertNotNil(GuideImages.render(.file(url), maxPixelWidth: 800).image)
    }

    func testOversizedSidecarCountsAsDamaged() throws {
        let url = try png("Step_01.png", width: 40, height: 30)
        let sidecar = folder.appendingPathComponent(FilenameGenerator.annotationsName(fromRaw: "Step_01.png"))
        try Data(count: UntrustedImageLimits.maxSidecarBytes + 1).write(to: sidecar)
        XCTAssertTrue(UntrustedImageLimits.sidecarTooLarge(forRaw: url))
        let render = GuideImages.render(.file(url), maxPixelWidth: 800)
        XCTAssertNil(render.image)
        XCTAssertTrue(render.sidecarDamaged)
    }
}
