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

    private func redaction(_ frame: CGRect) -> AnnotationObject {
        AnnotationObject(id: UUID(), kind: .blur, frame: frame,
                         color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1), strokeWidth: 2, redactionStyle: .solid)
    }

    /// Annotation frames are in points with a bottom-left origin; a bitmap's rows count from the top.
    /// An off-centre box makes a vertical flip show up as the wrong corner being dark.
    func testFlattensAnnotationsWithBottomLeftOrigin() throws {
        let url = try writeStep(white(width: 40, height: 40))
        try StorageManager(baseFolder: folder).saveAnnotations([redaction(CGRect(x: 2, y: 2, width: 10, height: 10))], rawURL: url)

        let result = GuideImages.render(.file(url), maxPixelWidth: 1600)
        XCTAssertFalse(result.sidecarDamaged)
        let bitmap = try decode(result.image)
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 7, y: 33)).brightnessComponent, 0.3, "box at the bottom-left")
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 7, y: 7)).brightnessComponent, 0.9, "top-left untouched")
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 33, y: 33)).brightnessComponent, 0.9, "bottom-right untouched")
    }

    func testFlattensAnnotationsOnRetinaImage() throws {
        // 40×40 points = 80×80 pixels; the frame is in points, so it covers pixels 4…24 from the left.
        let url = try writeStep(white(width: 40, height: 40, scale: 2))
        try StorageManager(baseFolder: folder).saveAnnotations([redaction(CGRect(x: 2, y: 2, width: 10, height: 10))], rawURL: url)

        let bitmap = try decode(GuideImages.render(.file(url), maxPixelWidth: 1600).image)
        XCTAssertEqual(bitmap.pixelsWide, 80)
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 14, y: 66)).brightnessComponent, 0.3, "box at the bottom-left")
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 14, y: 14)).brightnessComponent, 0.9, "top-left untouched")
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 50, y: 66)).brightnessComponent, 0.9, "right of the box untouched")
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
        let blue = testImage(width: 20, height: 20) {
            NSColor.blue.set()
            NSRect(x: 0, y: 0, width: 20, height: 20).fill()
        }
        let url = try writeStep(blue)
        try Data("not json".utf8).write(to: folder.appendingPathComponent(FilenameGenerator.annotationsName(fromRaw: "Step_01.png")))
        let result = GuideImages.render(.file(url), maxPixelWidth: 1600)
        XCTAssertTrue(result.sidecarDamaged)
        XCTAssertEqual(result.image?.pixelWidth, 20)
        let bitmap = try decode(result.image)
        for (x, y) in [(2, 2), (10, 10), (17, 17)] {
            let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y))
            XCTAssertGreaterThan(color.blueComponent, 0.9, "raw capture pixels, no annotation drawn")
            XCTAssertLessThan(color.redComponent, 0.1)
        }
    }

    /// JPEG has no alpha, so transparent areas must come out white rather than black.
    func testJPEGFallbackFlattensTransparencyToWhite() throws {
        let size = 64
        let provider = CGDataProvider(data: Data(count: size * size * 4) as CFData)!
        let clear = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let image = try XCTUnwrap(GuideImages.encode(clear, jpegThreshold: 10))
        XCTAssertEqual(image.kind, .jpeg)
        let color = try XCTUnwrap(try decode(image).colorAt(x: 32, y: 32))
        XCTAssertGreaterThan(color.brightnessComponent, 0.95)
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
