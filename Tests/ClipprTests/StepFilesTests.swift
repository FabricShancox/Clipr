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

    func testThumbnailCacheRemove() {
        let url = folder.appendingPathComponent("x.png")
        ThumbnailCache.shared.store(NSImage(size: CGSize(width: 2, height: 2)), for: url)
        XCTAssertNotNil(ThumbnailCache.shared.image(for: url))
        ThumbnailCache.shared.remove(url)
        XCTAssertNil(ThumbnailCache.shared.image(for: url))
    }
}
