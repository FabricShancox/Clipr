import XCTest
import Cocoa
@testable import Clipr

/// "Open Image…" must never let crop/resize or auto-save touch the user's own file: anything
/// opened from outside Clipr's capture folder (or that isn't a PNG) is imported as a fresh PNG
/// there first, and the editor works on that copy.
final class OpenImageImportTests: XCTestCase {
    var root: URL!
    var captures: URL!
    var outside: URL!
    var manager: StorageManager!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        captures = root.appendingPathComponent("Captures")
        outside = root.appendingPathComponent("Desktop")
        try! FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        manager = StorageManager(baseFolder: captures)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    private func image(_ color: NSColor = .red) -> NSImage {
        testImage(width: 4, height: 4) {
            color.set()
            NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        }
    }

    private func writeFile(_ name: String, type: NSBitmapImageRep.FileType, in folder: URL) throws -> URL {
        let rep = NSBitmapImageRep(cgImage: try XCTUnwrap(image().bitmap))
        let data = try XCTUnwrap(rep.representation(using: type, properties: [:]))
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func isPNG(_ url: URL) throws -> Bool {
        let bytes = try Data(contentsOf: url).prefix(8)
        return bytes == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }

    func testJPEGFromOutsideIsImportedAsPNGIntoCaptureFolder() throws {
        let original = try writeFile("photo.jpg", type: .jpeg, in: outside)
        let originalBytes = try Data(contentsOf: original)

        let imported = try manager.importForEditing(original, image: image())

        XCTAssertEqual(imported.deletingLastPathComponent().resolvingSymlinksInPath().path,
                       captures.resolvingSymlinksInPath().path)
        XCTAssertEqual(imported.lastPathComponent, "photo.png")
        XCTAssertTrue(try isPNG(imported))
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
    }

    func testCroppingAnImportedImageLeavesTheOriginalUntouched() throws {
        let original = try writeFile("photo.png", type: .png, in: outside)
        let originalBytes = try Data(contentsOf: original)

        let imported = try manager.importForEditing(original, image: image())
        try manager.overwriteRawCapture(image(.blue), rawURL: imported)
        try manager.saveAnnotations([], rawURL: imported)
        _ = try manager.saveEditedCapture(image(.green), rawURL: imported)

        XCTAssertNotEqual(imported.resolvingSymlinksInPath(), original.resolvingSymlinksInPath())
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
        // Nothing new was written next to the user's file.
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), ["photo.png"])
    }

    func testImportPicksAFreeNameRatherThanReplacingAnExistingCapture() throws {
        let existing = captures.appendingPathComponent("photo.png")
        try Data("keep".utf8).write(to: existing)
        let original = try writeFile("photo.jpg", type: .jpeg, in: outside)

        let imported = try manager.importForEditing(original, image: image())

        XCTAssertEqual(imported.lastPathComponent, "photo_1.png")
        XCTAssertEqual(try Data(contentsOf: existing), Data("keep".utf8))
    }

    func testPNGAlreadyInCaptureFolderIsEditedInPlace() throws {
        let capture = try manager.saveRawCapture(image(), date: Date())
        XCTAssertEqual(try manager.importForEditing(capture, image: image()), capture)
    }

    func testNonPNGInsideCaptureFolderIsStillImported() throws {
        let jpeg = try writeFile("shot.jpg", type: .jpeg, in: captures)
        let bytes = try Data(contentsOf: jpeg)
        let imported = try manager.importForEditing(jpeg, image: image())
        XCTAssertEqual(imported.lastPathComponent, "shot.png")
        XCTAssertEqual(try Data(contentsOf: jpeg), bytes)
    }

    func testOverwriteRefusesToPutPNGBytesUnderAnotherExtension() throws {
        let jpeg = try writeFile("photo.jpg", type: .jpeg, in: outside)
        let bytes = try Data(contentsOf: jpeg)
        XCTAssertThrowsError(try manager.overwriteRawCapture(image(.blue), rawURL: jpeg))
        XCTAssertEqual(try Data(contentsOf: jpeg), bytes)
    }
}
