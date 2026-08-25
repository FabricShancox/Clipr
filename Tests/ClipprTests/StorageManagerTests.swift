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

    func testCollisionHandlingRenamesOnFilesystemClash() throws {
        // Save two images with the same timestamp to force a collision
        let sameDate = Date()
        let url1 = try manager.saveRawCapture(makeTestImage(), date: sameDate)
        let url2 = try manager.saveRawCapture(makeTestImage(), date: sameDate)

        // Both files should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: url1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url2.path))

        // They should have different names
        XCTAssertNotEqual(url1.lastPathComponent, url2.lastPathComponent)

        // First file should have no suffix (original name from FilenameGenerator)
        XCTAssertFalse(url1.lastPathComponent.contains("_1.png"))

        // Second file should have _1 suffix
        XCTAssertTrue(url2.lastPathComponent.contains("_1.png"))

        // Both files should be readable and non-empty
        let data1 = try Data(contentsOf: url1)
        let data2 = try Data(contentsOf: url2)
        XCTAssertGreaterThan(data1.count, 0)
        XCTAssertGreaterThan(data2.count, 0)
    }
}
