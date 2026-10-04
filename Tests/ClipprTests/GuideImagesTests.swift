// Tests/ClipprTests/GuideImagesTests.swift
import XCTest
import Cocoa
@testable import Clipr

final class GuideImagesTests: XCTestCase {
    var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Writes `image` as a step PNG the way capture does, returning its URL.
    private func writeStep(_ image: NSImage, name: String = "Step_01.png") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try XCTUnwrap(StepFiles.pngData(image)).write(to: url)
        return url
    }

    private func white(width: Int, height: Int, scale: CGFloat = 1) -> NSImage {
        testImage(width: width, height: height, scale: scale) {
            NSColor.white.set()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
    }

    /// Random pixels: the worst case for PNG, so its encoding is far larger than a JPEG's.
    private func noise(width: Int, height: Int) -> NSImage {
        let bytes = (0..<(width * height * 4)).map { $0 % 4 == 3 ? UInt8(255) : UInt8.random(in: 0...255) }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }

    private func decode(_ image: GuideImage?) throws -> NSBitmapImageRep {
        try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image).data))
    }

    func testFlattensAnnotationsOntoImage() throws {
        let url = try writeStep(white(width: 40, height: 40))
        let box = AnnotationObject(id: UUID(), kind: .blur, frame: CGRect(x: 10, y: 10, width: 20, height: 20),
                                   color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1), strokeWidth: 2, redactionStyle: .solid)
        try StorageManager(baseFolder: folder).saveAnnotations([box], rawURL: url)

        let result = GuideImages.render(.file(url), maxPixelWidth: 1600)
        XCTAssertFalse(result.sidecarDamaged)
        let bitmap = try decode(result.image)
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 20, y: 20)).brightnessComponent, 0.3, "redaction drawn in the middle")
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 2, y: 2)).brightnessComponent, 0.9, "corner untouched")
    }

    func testDownsamplesToMaxWidth() throws {
        let url = try writeStep(white(width: 3000, height: 100))
        let image = try XCTUnwrap(GuideImages.render(.file(url), maxPixelWidth: 1600).image)
        XCTAssertEqual(image.pixelWidth, 1600)
        XCTAssertEqual(image.pixelHeight, 53)
    }

    func testNeverEnlarges() throws {
        let url = try writeStep(white(width: 300, height: 100))
        let image = try XCTUnwrap(GuideImages.render(.file(url), maxPixelWidth: 1600).image)
        XCTAssertEqual(image.pixelWidth, 300)
    }

    func testRetinaImageCapsPixelsNotPoints() throws {
        // 100×50 points, 200×100 pixels: the cap applies to the pixels.
        let url = try writeStep(white(width: 100, height: 50, scale: 2))
        let capped = try XCTUnwrap(GuideImages.render(.file(url), maxPixelWidth: 150).image)
        XCTAssertEqual(capped.pixelWidth, 150)
        XCTAssertEqual(capped.pixelHeight, 75)
        let full = try XCTUnwrap(GuideImages.render(.file(url), maxPixelWidth: 1600).image)
        XCTAssertEqual(full.pixelWidth, 200, "every Retina pixel kept when there's room")
    }

    func testWidthsPerSize() {
        XCTAssertEqual(ImageSize.allCases.map(GuideImages.maxPixelWidth(for:)), [640, 960, 1280, 1600])
        XCTAssertEqual(GuideImages.jpegThreshold, 1_500_000)
        XCTAssertEqual(GuideImages.zoomPixelWidth, 480)
    }

    func testSmallImageStaysPNG() throws {
        let url = try writeStep(white(width: 50, height: 50))
        let image = try XCTUnwrap(GuideImages.render(.file(url), maxPixelWidth: 1600).image)
        XCTAssertEqual(image.kind, .png)
        XCTAssertEqual(Array(image.data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testLargePNGFallsBackToJPEG() throws {
        let url = try writeStep(noise(width: 200, height: 200))
        let image = try XCTUnwrap(GuideImages.render(.file(url), maxPixelWidth: 1600, jpegThreshold: 1_000).image)
        XCTAssertEqual(image.kind, .jpeg)
        XCTAssertEqual(Array(image.data.prefix(2)), [0xFF, 0xD8])
        XCTAssertEqual(image.pixelWidth, 200)
    }

    func testDamagedSidecarGivesRawImageAndFlag() throws {
        let url = try writeStep(white(width: 20, height: 20))
        try Data("not json".utf8).write(to: folder.appendingPathComponent(FilenameGenerator.annotationsName(fromRaw: "Step_01.png")))
        let result = GuideImages.render(.file(url), maxPixelWidth: 1600)
        XCTAssertTrue(result.sidecarDamaged)
        XCTAssertEqual(result.image?.pixelWidth, 20)
    }

    func testMissingOrUnreadableImageGivesNil() throws {
        XCTAssertNil(GuideImages.render(.missing, maxPixelWidth: 1600).image)
        XCTAssertNil(GuideImages.render(.file(folder.appendingPathComponent("nope.png")), maxPixelWidth: 1600).image)
        let garbage = folder.appendingPathComponent("Step_09.png")
        try Data([1, 2, 3]).write(to: garbage)
        let result = GuideImages.render(.file(garbage), maxPixelWidth: 1600)
        XCTAssertNil(result.image)
        XCTAssertFalse(result.sidecarDamaged)
    }
}
