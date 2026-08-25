import XCTest
import Cocoa
@testable import Clipr

final class StorageManagerTests: XCTestCase {
    var tempDir: URL!
    var manager: StorageManager!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        manager = StorageManager(baseFolder: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeTestImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.set()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        return image
    }

    func testSaveRawCaptureWritesFile() throws {
        let url = try manager.saveRawCapture(makeTestImage(), date: Date())
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.deletingLastPathComponent().path, tempDir.path)
    }

    func testSaveEditedCaptureNamesRelativeToRaw() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        let editedURL = try manager.saveEditedCapture(makeTestImage(), rawURL: rawURL)
        XCTAssertTrue(editedURL.lastPathComponent.hasSuffix("_edited.png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: editedURL.path))
    }

    func testCreateSessionFolderAndSaveStep() throws {
        let sessionFolder = try manager.createSessionFolder(date: Date())
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionFolder.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        let stepURL = try manager.saveStep(makeTestImage(), index: 1, in: sessionFolder)
        XCTAssertEqual(stepURL.lastPathComponent, "Step_01.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stepURL.path))
    }
}
