import XCTest
import Cocoa
@testable import Clipr

final class DecodeLimitsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private let red = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)

    func testImageSizeLimits() {
        XCTAssertTrue(DecodeLimits.isAcceptableImageSize(width: 6016, height: 3384))
        XCTAssertTrue(DecodeLimits.isAcceptableImageSize(width: 3000, height: 30_000))
        XCTAssertFalse(DecodeLimits.isAcceptableImageSize(width: 60_000, height: 60_000))
        XCTAssertFalse(DecodeLimits.isAcceptableImageSize(width: 20_000, height: 20_000), "400 MP")
        XCTAssertFalse(DecodeLimits.isAcceptableImageSize(width: 0, height: 10))
    }

    func testAnOrdinaryImageLoads() throws {
        let url = folder.appendingPathComponent("small.png")
        let image = testImage(width: 8, height: 6) { NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 8, height: 6).fill() }
        let rep = NSBitmapImageRep(cgImage: try XCTUnwrap(image.bitmap))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        guard case .loaded = DecodeLimits.loadImage(at: url) else { return XCTFail("expected the image to load") }
    }

    func testAnOversizedImageIsRefusedFromItsHeader() throws {
        // A tiny, highly compressible grayscale PNG that declares 40,000 × 1 — over the side limit,
        // and cheap to create.
        let url = folder.appendingPathComponent("wide.png")
        let context = try XCTUnwrap(CGContext(data: nil, width: 40_000, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        let rep = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        guard case .tooLarge(let width, _) = DecodeLimits.loadImage(at: url) else { return XCTFail("expected a refusal") }
        XCTAssertEqual(width, 40_000)
    }

    func testANonImageIsUnreadable() throws {
        let url = folder.appendingPathComponent("fake.png")
        try Data("not an image".utf8).write(to: url)
        guard case .unreadable = DecodeLimits.loadImage(at: url) else { return XCTFail("expected unreadable") }
    }

    func testOutOfRangeSidecarValuesAreRefused() {
        let fine = AnnotationObject(id: UUID(), kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10), color: red, strokeWidth: 2)
        XCTAssertTrue(DecodeLimits.areAcceptable([fine]))
        var huge = fine
        huge.frame = CGRect(x: 0, y: 0, width: 1e12, height: 10)
        XCTAssertFalse(DecodeLimits.areAcceptable([huge]))
        var fat = fine
        fat.strokeWidth = 1e9
        XCTAssertFalse(DecodeLimits.areAcceptable([fat]))
        let bigText = AnnotationObject(id: UUID(), kind: .text("x", TextStyle(fontSize: 1e7, bold: false, italic: false, border: false, horizontalAlign: .left, verticalAlign: .top)),
                                       frame: .zero, color: red, strokeWidth: 1)
        XCTAssertFalse(DecodeLimits.areAcceptable([bigText]))
        XCTAssertFalse(DecodeLimits.areAcceptable(Array(repeating: fine, count: DecodeLimits.maxAnnotations + 1)))
    }

    func testAnOversizedSidecarReadsAsCorruptAndIsNotDecoded() throws {
        let storage = StorageManager(baseFolder: folder)
        let raw = folder.appendingPathComponent("Shot.png")
        let sidecar = folder.appendingPathComponent(FilenameGenerator.annotationsName(fromRaw: raw.lastPathComponent))
        try Data(count: DecodeLimits.maxSidecarBytes + 1).write(to: sidecar)
        guard case .corrupt(let error) = storage.readAnnotations(rawURL: raw) else { return XCTFail("expected corrupt") }
        XCTAssertTrue(error is SidecarLimitError)
    }
}
