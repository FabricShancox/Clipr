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
        let image = testImage(width: 4, height: 4) {
            NSColor.red.set()
            NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        }
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

    func testSaveEditedCaptureOverwritesOnRepeatedSave() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        let firstURL = try manager.saveEditedCapture(makeTestImage(), rawURL: rawURL)
        let secondURL = try manager.saveEditedCapture(makeTestImage(), rawURL: rawURL)
        XCTAssertEqual(firstURL, secondURL)
        let siblingCount = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("_edited") }
            .count
        XCTAssertEqual(siblingCount, 1)
    }

    func testLoadAnnotationsReturnsEmptyWhenNeverSaved() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        XCTAssertEqual(manager.loadAnnotations(rawURL: rawURL), [])
    }

    func testSaveAnnotationsRoundTripsThroughLoad() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        let annotation = AnnotationObject(
            id: UUID(), kind: .text("hello", .default),
            frame: CGRect(x: 1, y: 2, width: 3, height: 4),
            color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1), strokeWidth: 2
        )
        try manager.saveAnnotations([annotation], rawURL: rawURL)
        XCTAssertEqual(manager.loadAnnotations(rawURL: rawURL), [annotation])
    }

    // MARK: - readAnnotations: missing vs corrupt

    func testReadAnnotationsReportsMissingWhenNeverSaved() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        guard case .missing = manager.readAnnotations(rawURL: rawURL) else {
            return XCTFail("expected .missing")
        }
    }

    func testReadAnnotationsReportsCorruptRatherThanEmpty() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        let sidecar = tempDir.appendingPathComponent(
            FilenameGenerator.annotationsName(fromRaw: rawURL.lastPathComponent)
        )
        try Data("{ this is not the array we expect".utf8).write(to: sidecar)

        guard case .corrupt = manager.readAnnotations(rawURL: rawURL) else {
            return XCTFail("a sidecar that exists but won't decode must not look like a fresh capture")
        }
    }

    /// The safety property: an unreadable sidecar is moved aside, never dropped, so the next
    /// auto-save writes a new file instead of overwriting recoverable data.
    func testQuarantineMovesTheUnreadableSidecarAsideWithoutLosingIt() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        let sidecar = tempDir.appendingPathComponent(
            FilenameGenerator.annotationsName(fromRaw: rawURL.lastPathComponent)
        )
        let original = "irreplaceable but unreadable"
        try Data(original.utf8).write(to: sidecar)

        let backup = try XCTUnwrap(manager.quarantineAnnotations(rawURL: rawURL))

        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path), "original path must be free")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), original, "contents preserved")
        XCTAssertTrue(backup.lastPathComponent.hasSuffix(".bak"))
    }

    func testQuarantineIsANoOpWhenThereIsNoSidecar() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        XCTAssertNil(manager.quarantineAnnotations(rawURL: rawURL))
    }

    func testQuarantineTwiceKeepsBothBackups() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        let sidecar = tempDir.appendingPathComponent(
            FilenameGenerator.annotationsName(fromRaw: rawURL.lastPathComponent)
        )
        try Data("first".utf8).write(to: sidecar)
        let first = try XCTUnwrap(manager.quarantineAnnotations(rawURL: rawURL))
        try Data("second".utf8).write(to: sidecar)
        let second = try XCTUnwrap(manager.quarantineAnnotations(rawURL: rawURL))

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
    }

    func testDeleteAnnotationsRemovesSidecar() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        let annotation = AnnotationObject(
            id: UUID(), kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10),
            color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 1), strokeWidth: 1
        )
        try manager.saveAnnotations([annotation], rawURL: rawURL)
        manager.deleteAnnotations(rawURL: rawURL)
        XCTAssertEqual(manager.loadAnnotations(rawURL: rawURL), [])
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

    /// A save-folder change in Preferences re-points the existing (long-lived) StorageManager rather
    /// than rebuilding it, so writes must follow the new folder immediately.
    // MARK: - Empty sidecars

    private func sidecarURL(for rawURL: URL) -> URL {
        rawURL.deletingLastPathComponent().appendingPathComponent(FilenameGenerator.annotationsName(fromRaw: rawURL.lastPathComponent))
    }

    func testSavingNoAnnotationsWritesNoSidecar() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        try manager.saveAnnotations([], rawURL: rawURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL(for: rawURL).path))
        if case .missing = manager.readAnnotations(rawURL: rawURL) {} else { XCTFail("expected no sidecar") }
    }

    func testSavingNoAnnotationsRemovesAStaleEmptySidecar() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        try Data("[]".utf8).write(to: sidecarURL(for: rawURL))
        try manager.saveAnnotations([], rawURL: rawURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL(for: rawURL).path))
    }

    func testDeletingTheLastAnnotationRemovesTheSidecar() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        let annotation = AnnotationObject(
            id: UUID(), kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10),
            color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 1), strokeWidth: 1
        )
        try manager.saveAnnotations([annotation], rawURL: rawURL)
        try manager.saveAnnotations([], rawURL: rawURL)
        XCTAssertEqual(manager.loadAnnotations(rawURL: rawURL), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarURL(for: rawURL).path))
    }

    // MARK: - Deleting a Recent

    func testDeleteCaptureMovesTheCaptureAndItsCompanionsToTheTrash() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        let editedURL = try manager.saveEditedCapture(makeTestImage(), rawURL: rawURL)
        let annotation = AnnotationObject(
            id: UUID(), kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10),
            color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 1), strokeWidth: 1
        )
        try manager.saveAnnotations([annotation], rawURL: rawURL)
        let trash = tempDir.appendingPathComponent("FakeTrash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        var trashed: [String] = []
        manager.trashItem = { url in
            trashed.append(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: trash.appendingPathComponent(url.lastPathComponent))
        }

        try manager.deleteCapture(rawURL: rawURL)

        XCTAssertEqual(trashed.first, rawURL.lastPathComponent)
        XCTAssertTrue(trashed.contains(editedURL.lastPathComponent))
        XCTAssertEqual(trashed.count, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: rawURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.appendingPathComponent(rawURL.lastPathComponent).path),
                      "the capture is recoverable, not destroyed")
    }

    func testDeleteCaptureReportsAFailureAndLeavesCompanionsAlone() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        let editedURL = try manager.saveEditedCapture(makeTestImage(), rawURL: rawURL)
        manager.trashItem = { _ in throw CocoaError(.fileWriteNoPermission) }

        XCTAssertThrowsError(try manager.deleteCapture(rawURL: rawURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rawURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: editedURL.path))
    }

    func testDeleteCaptureOfANeverEditedCaptureOnlyTrashesTheRawFile() throws {
        let rawURL = try manager.saveRawCapture(makeTestImage(), date: Date())
        var trashed: [URL] = []
        manager.trashItem = { trashed.append($0); try FileManager.default.removeItem(at: $0) }
        try manager.deleteCapture(rawURL: rawURL)
        XCTAssertEqual(trashed, [rawURL])
    }

    func testReassigningBaseFolderRedirectsSubsequentWrites() throws {
        let newFolder = tempDir.appendingPathComponent("Relocated")
        manager.baseFolder = newFolder

        let url = try manager.saveRawCapture(makeTestImage(), date: Date())
        XCTAssertEqual(url.deletingLastPathComponent().path, newFolder.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let sessionFolder = try manager.createSessionFolder(date: Date())
        XCTAssertEqual(sessionFolder.deletingLastPathComponent().path, newFolder.path)
    }
}
