import XCTest
import Cocoa
@testable import Clipr

/// "Save As…" exports a copy in a format the user picks, unlike the app's own capture storage
/// which is always PNG.
final class ExportTests: XCTestCase {
    private var tempDir: URL!
    private var manager: StorageManager!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = StorageManager(baseFolder: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Pixel-exact, and genuinely transparent on one half so the JPEG path has alpha to deal with.
    private func halfTransparentImage(width: Int, height: Int) -> NSImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let cg = ctx.makeImage()!
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }

    func testExportsPNGPreservingTransparency() throws {
        let url = tempDir.appendingPathComponent("out.png")
        try manager.export(halfTransparentImage(width: 40, height: 20), to: url, format: .png)

        let written = try XCTUnwrap(NSImage(contentsOf: url))
        let cg = try XCTUnwrap(written.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let transparentSide = try XCTUnwrap(bitmap.colorAt(x: 35, y: 10))
        XCTAssertLessThan(transparentSide.alphaComponent, 0.1, "PNG should keep the transparent half")
    }

    /// JPEG has no alpha channel. Without compositing first, the transparent half encodes as
    /// black — a capture whose canvas was resized outward would export with black bands.
    func testExportsJPEGCompositedOnWhiteRatherThanBlack() throws {
        let url = tempDir.appendingPathComponent("out.jpg")
        try manager.export(halfTransparentImage(width: 40, height: 20), to: url, format: .jpeg)

        let written = try XCTUnwrap(NSImage(contentsOf: url))
        let cg = try XCTUnwrap(written.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let formerlyTransparent = try XCTUnwrap(bitmap.colorAt(x: 35, y: 10))
        XCTAssertGreaterThan(formerlyTransparent.brightnessComponent, 0.8,
                             "the transparent area should become white, not black")
    }

    func testExportedFileIsActuallyInTheRequestedFormat() throws {
        let png = tempDir.appendingPathComponent("a.png")
        let jpeg = tempDir.appendingPathComponent("b.jpg")
        try manager.export(halfTransparentImage(width: 20, height: 20), to: png, format: .png)
        try manager.export(halfTransparentImage(width: 20, height: 20), to: jpeg, format: .jpeg)

        // Magic numbers rather than trusting the extension.
        let pngHeader = try Data(contentsOf: png).prefix(8)
        XCTAssertEqual(Array(pngHeader), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let jpegHeader = try Data(contentsOf: jpeg).prefix(3)
        XCTAssertEqual(Array(jpegHeader), [0xFF, 0xD8, 0xFF])
    }

    func testExportOverwritesAnExistingFileTheUserPicked() throws {
        // The save panel already asks about replacing, so export must not silently suffix.
        let url = tempDir.appendingPathComponent("fixed.png")
        try Data("stale".utf8).write(to: url)
        try manager.export(halfTransparentImage(width: 10, height: 10), to: url, format: .png)

        XCTAssertEqual(Array(try Data(contentsOf: url).prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tempDir.path).count, 1,
                       "must write to exactly the chosen path, not a suffixed sibling")
    }

    func testFormatExtensionsAndTypesLineUp() {
        XCTAssertEqual(ExportFormat.png.fileExtension, "png")
        XCTAssertEqual(ExportFormat.jpeg.fileExtension, "jpg")
        XCTAssertFalse(ExportFormat.png.needsOpaqueBackground)
        XCTAssertTrue(ExportFormat.jpeg.needsOpaqueBackground)
    }
}
