import XCTest
import Cocoa
@testable import Clipr

final class StepFilesTests: XCTestCase {
    var folder: URL!
    var trash: URL!

    override func setUp() {
        super.setUp()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        folder = root.appendingPathComponent("Session")
        trash = root.appendingPathComponent("Trash")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
        super.tearDown()
    }

    private func touch(_ name: String) {
        FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data([1]))
    }
    private func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
    }
    /// A stand-in Trash so tests never touch the user's real one.
    private var fakeFiles: StepFiles {
        StepFiles(
            trashItem: { [trash] url in
                let dest = trash!.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) }
        )
    }

    func testCompanionsFindsExistingFilesOnly() {
        touch("Step_03.png"); touch("Step_03_annotations.json"); touch("Step_03_edited.png")
        let names = StepFiles.companions(of: "Step_03.png", in: folder).map(\.lastPathComponent)
        XCTAssertEqual(Set(names), ["Step_03.png", "Step_03_annotations.json", "Step_03_edited.png"])
        touch("Step_03_zoom.png")
        XCTAssertEqual(StepFiles.companions(of: "Step_03.png", in: folder).count, 4)
        // Prefix collision check: similar names are not included.
        touch("Step_030.png"); touch("Step_03x_annotations.json")
        XCTAssertFalse(StepFiles.companions(of: "Step_03.png", in: folder).map(\.lastPathComponent).contains("Step_030.png"))
        XCTAssertFalse(StepFiles.companions(of: "Step_03.png", in: folder).map(\.lastPathComponent).contains("Step_03x_annotations.json"))
    }

    func testThumbnailPrefersEdited() {
        touch("Step_01.png")
        XCTAssertEqual(StepFiles.thumbnailURL(of: "Step_01.png", in: folder).lastPathComponent, "Step_01.png")
        touch("Step_01_edited.png")
        XCTAssertEqual(StepFiles.thumbnailURL(of: "Step_01.png", in: folder).lastPathComponent, "Step_01_edited.png")
    }

    func testTrashAndRestoreRoundTrip() throws {
        touch("Step_02.png"); touch("Step_02_annotations.json"); touch("Step_02_zoom.png")
        let trashed = try fakeFiles.trash("Step_02.png", in: folder)
        XCTAssertEqual(trashed.moves.count, 3)
        XCTAssertFalse(exists("Step_02.png")); XCTAssertFalse(exists("Step_02_zoom.png"))
        try fakeFiles.restore(trashed)
        XCTAssertTrue(exists("Step_02.png")); XCTAssertTrue(exists("Step_02_annotations.json")); XCTAssertTrue(exists("Step_02_zoom.png"))
    }

    func testTrashFailsWhenRawCannotMove() {
        touch("Step_04.png")
        let failing = StepFiles(trashItem: { _ in throw CocoaError(.fileWriteNoPermission) }, moveItem: { _, _ in })
        XCTAssertThrowsError(try failing.trash("Step_04.png", in: folder))
        XCTAssertTrue(exists("Step_04.png"))
    }

    func testRestoreFailsCleanlyWhenTrashedFileIsGone() throws {
        touch("Step_05.png"); touch("Step_05_zoom.png")
        let trashed = try fakeFiles.trash("Step_05.png", in: folder)
        try FileManager.default.removeItem(at: trashed.moves[0].trashed)  // "Trash emptied"
        XCTAssertThrowsError(try fakeFiles.restore(trashed)) {
            XCTAssertEqual($0 as? StepFilesError, .trashedFileMissing("Step_05.png"))
        }
        XCTAssertFalse(exists("Step_05.png")); XCTAssertFalse(exists("Step_05_zoom.png"))  // nothing half-restored
    }

    func testRestoreRollsBackOnMoveItemFailure() throws {
        touch("Step_06.png"); touch("Step_06_annotations.json"); touch("Step_06_zoom.png")
        let trashed = try fakeFiles.trash("Step_06.png", in: folder)
        XCTAssertEqual(trashed.moves.count, 3)
        // Verify files are in Trash
        XCTAssertFalse(exists("Step_06.png")); XCTAssertFalse(exists("Step_06_annotations.json")); XCTAssertFalse(exists("Step_06_zoom.png"))
        // Create a failing moveItem that throws on the second call (after Step_06.png is moved back)
        var moveCount = 0
        let failing = StepFiles(
            trashItem: { [trash] url in
                let dest = trash!.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            moveItem: { source, dest in
                moveCount += 1
                if moveCount == 2 { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.moveItem(at: source, to: dest)
            }
        )
        // Restore should fail and roll back the first move
        XCTAssertThrowsError(try failing.restore(trashed)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .fileWriteNoPermission)
        }
        // All files should still be in Trash, none in session folder (all-or-nothing)
        XCTAssertFalse(exists("Step_06.png")); XCTAssertFalse(exists("Step_06_annotations.json")); XCTAssertFalse(exists("Step_06_zoom.png"))
        // All trashed files still exist at their Trash URLs
        for move in trashed.moves {
            XCTAssertTrue(FileManager.default.fileExists(atPath: move.trashed.path), "File should still be in Trash: \(move.trashed.lastPathComponent)")
        }
    }

    func testTrashAllMovesEveryCompanion() throws {
        touch("Step_07.png"); touch("Step_07_annotations.json"); touch("Step_07_edited.png")
        let trashed = try fakeFiles.trashAll("Step_07.png", in: folder)
        XCTAssertEqual(trashed.moves.count, 3)
        XCTAssertFalse(exists("Step_07.png")); XCTAssertFalse(exists("Step_07_annotations.json")); XCTAssertFalse(exists("Step_07_edited.png"))
    }

    /// Replacing an image must not leave an old `_edited.png` behind to shadow the new one, so a
    /// companion that won't move puts everything back and fails the whole trash.
    func testTrashAllPutsEverythingBackWhenACompanionWontMove() throws {
        touch("Step_08.png"); touch("Step_08_annotations.json"); touch("Step_08_edited.png")
        let stuck = StepFiles(
            trashItem: { [trash] url in
                if url.lastPathComponent == "Step_08_edited.png" { throw CocoaError(.fileWriteNoPermission) }
                let dest = trash!.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) }
        )
        XCTAssertThrowsError(try stuck.trashAll("Step_08.png", in: folder))
        XCTAssertTrue(exists("Step_08.png")); XCTAssertTrue(exists("Step_08_annotations.json")); XCTAssertTrue(exists("Step_08_edited.png"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), [])
    }

    /// A phone photo stored sideways with an EXIF orientation must come out upright.
    func testReplacementPNGAppliesEXIFOrientation() throws {
        let url = folder.appendingPathComponent("photo.jpg")
        let source = testImage(width: 6, height: 2) { NSColor.red.set(); NSRect(x: 0, y: 0, width: 6, height: 2).fill() }
        let cg = try XCTUnwrap(source.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        let png = try XCTUnwrap(StepFiles.replacementPNG(from: url))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(rep.pixelsWide, 2)
        XCTAssertEqual(rep.pixelsHigh, 6)
    }

    func testReplacementPNGIsNilForAFileThatWontDecode() throws {
        let url = folder.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: url)
        XCTAssertNil(StepFiles.replacementPNG(from: url))
    }

    func testThumbnailCacheRemove() {
        let url = folder.appendingPathComponent("x.png")
        ThumbnailCache.shared.store(NSImage(size: CGSize(width: 2, height: 2)), for: url)
        XCTAssertNotNil(ThumbnailCache.shared.image(for: url))
        ThumbnailCache.shared.remove(url)
        XCTAssertNil(ThumbnailCache.shared.image(for: url))
    }
}
