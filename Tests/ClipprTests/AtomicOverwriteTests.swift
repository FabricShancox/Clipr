import XCTest
import Cocoa
@testable import Clipr

/// Overwriting a capture must never delete first: a failed write has to leave the old file there.
final class AtomicOverwriteTests: XCTestCase {
    var tempDir: URL!
    var manager: StorageManager!

    struct InjectedFailure: Error {}

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

    private func image(_ color: NSColor) -> NSImage {
        testImage(width: 4, height: 4) {
            color.set()
            NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        }
    }

    func testFailedRawOverwriteLeavesTheOriginalInPlace() throws {
        let raw = try manager.saveRawCapture(image(.red), date: Date())
        let before = try Data(contentsOf: raw)

        manager.writeData = { _, _ in throw InjectedFailure() }
        XCTAssertThrowsError(try manager.overwriteRawCapture(image(.blue), rawURL: raw))

        XCTAssertEqual(try Data(contentsOf: raw), before)
    }

    func testFailedEditedOverwriteLeavesThePreviousExportInPlace() throws {
        let raw = try manager.saveRawCapture(image(.red), date: Date())
        let edited = try manager.saveEditedCapture(image(.green), rawURL: raw)
        let before = try Data(contentsOf: edited)

        manager.writeData = { _, _ in throw InjectedFailure() }
        XCTAssertThrowsError(try manager.saveEditedCapture(image(.blue), rawURL: raw))

        XCTAssertEqual(try Data(contentsOf: edited), before)
    }

    func testDefaultWriterReplacesContentsWithoutLeavingTempFiles() throws {
        let raw = try manager.saveRawCapture(image(.red), date: Date())
        let before = try Data(contentsOf: raw)
        try manager.overwriteRawCapture(image(.blue), rawURL: raw)
        XCTAssertNotEqual(try Data(contentsOf: raw), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tempDir.path), [raw.lastPathComponent])
    }
}
