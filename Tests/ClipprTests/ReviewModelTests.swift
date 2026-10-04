// Tests/ClipprTests/ReviewModelTests.swift
import XCTest
@testable import Clipr

@MainActor
final class ReviewModelTests: XCTestCase {
    var root: URL!
    var folder: URL!
    var trash: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        folder = root.appendingPathComponent("Session")
        trash = root.appendingPathComponent("Trash")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        var steps: [StepRecord] = []
        for (i, name) in ["a", "b", "c", "d"].enumerated() {
            let file = String(format: "Step_%02d.png", i + 1)
            FileManager.default.createFile(atPath: folder.appendingPathComponent(file).path, contents: Data([1]))
            steps.append(StepRecord(id: UUID(), file: file, kind: .click, caption: name, clickPoint: nil,
                                    zoomFile: nil, appName: "Safari", capturedAt: Date(timeIntervalSince1970: 0)))
        }
        try SessionManifestStore.save(SessionManifest(createdAt: Date(timeIntervalSince1970: 0), steps: steps), in: folder)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

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

    private func makeModel(captionDelay: TimeInterval = 0.05, save: ((SessionManifest, URL) throws -> Void)? = nil) -> ReviewModel {
        ReviewModel(folder: folder, files: fakeFiles, save: save ?? SessionManifestStore.saveSafely, captionDelay: captionDelay)
    }
    private func captions(_ m: SessionManifest) -> [String?] { m.steps.map(\.caption) }
    private var onDisk: SessionManifest { SessionManifestStore.load(from: folder) }

    func testMovePersistsAndUndoRedo() {
        let model = makeModel()
        model.move(fromOffsets: [3], toOffset: 0)
        XCTAssertEqual(captions(onDisk), ["d", "a", "b", "c"])
        XCTAssertEqual(model.undoManager.undoActionName, "Move Steps")
        model.undoManager.undo()
        XCTAssertEqual(captions(onDisk), ["a", "b", "c", "d"])
        model.undoManager.redo()
        XCTAssertEqual(captions(onDisk), ["d", "a", "b", "c"])
    }

    func testMoveKeepsSelectionByID() {
        let model = makeModel()
        let ids = [model.manifest.steps[0].id, model.manifest.steps[2].id]
        model.selection = Set(ids)
        model.move(fromOffsets: [0, 2], toOffset: 4)
        XCTAssertEqual(model.selection, Set(ids))
        XCTAssertEqual(captions(model.manifest), ["b", "d", "a", "c"])
    }

    func testMoveSelectionByOne() {
        let model = makeModel()
        model.selection = [model.manifest.steps[1].id]
        model.moveSelection(by: -1)
        XCTAssertEqual(captions(onDisk), ["b", "a", "c", "d"])
        model.moveSelection(by: -1)  // already first: no-op
        XCTAssertEqual(captions(onDisk), ["b", "a", "c", "d"])
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        XCTAssertEqual(captions(onDisk), ["a", "c", "b", "d"])
    }

    func testCaptionDebounceWritesOnceAfterPause() async throws {
        var writes = 0
        let model = makeModel(captionDelay: 0.2, save: { m, f in writes += 1; try SessionManifestStore.saveSafely(m, in: f) })
        let id = model.manifest.steps[0].id
        model.editCaption("x", for: id)
        model.editCaption("xy", for: id)
        model.editCaption("xyz", for: id)
        XCTAssertEqual(writes, 0)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(writes, 1)
        XCTAssertEqual(onDisk.steps[0].caption, "xyz")
        XCTAssertEqual(model.undoManager.undoActionName, "Edit Caption")
        model.undoManager.undo()
        XCTAssertEqual(onDisk.steps[0].caption, "a")
    }

    func testCommitCaptionIsImmediateAndEmptyClears() {
        let model = makeModel(captionDelay: 10)
        let id = model.manifest.steps[1].id
        model.commitCaption("  ", for: id)
        XCTAssertNil(onDisk.steps[1].caption)
    }

    func testUnchangedCaptionRegistersNoUndo() {
        let model = makeModel()
        model.commitCaption("a", for: model.manifest.steps[0].id)
        XCTAssertFalse(model.undoManager.canUndo)
    }

    func testFlushPendingCaptionSavesImmediately() {
        let model = makeModel(captionDelay: 10)
        let id = model.manifest.steps[2].id
        model.editCaption("typed", for: id)
        model.flushPendingCaption()
        XCTAssertEqual(onDisk.steps[2].caption, "typed")
    }

    func testDeleteTrashesFilesAndUndoRestores() {
        let model = makeModel()
        FileManager.default.createFile(atPath: folder.appendingPathComponent("Step_02_zoom.png").path, contents: Data([1]))
        model.selection = [model.manifest.steps[1].id]
        model.deleteSelection()
        XCTAssertEqual(captions(onDisk), ["a", "c", "d"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Step_02.png").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Step_02_zoom.png").path))
        XCTAssertEqual(model.selection, [model.manifest.steps[1].id])  // the step now at the deleted position
        XCTAssertEqual(model.undoManager.undoActionName, "Delete Steps")
        model.undoManager.undo()
        XCTAssertEqual(captions(onDisk), ["a", "b", "c", "d"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Step_02_zoom.png").path))
        model.undoManager.redo()
        XCTAssertEqual(captions(onDisk), ["a", "c", "d"])
    }

    func testDeleteAllThenUndoRestoresEverything() {
        let model = makeModel()
        model.selection = Set(model.manifest.steps.map(\.id))
        model.deleteSelection()
        XCTAssertTrue(model.manifest.steps.isEmpty)
        XCTAssertTrue(model.selection.isEmpty)
        model.undoManager.undo()
        XCTAssertEqual(captions(onDisk), ["a", "b", "c", "d"])
    }

    func testPartialTrashFailureKeepsFailedStepAndShowsBanner() {
        var calls = 0
        let flaky = StepFiles(
            trashItem: { [trash] url in
                calls += 1
                if url.lastPathComponent == "Step_03.png" { throw CocoaError(.fileWriteNoPermission) }
                let dest = trash!.appendingPathComponent(UUID().uuidString)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) }
        )
        let model = ReviewModel(folder: folder, files: flaky, captionDelay: 0.05)
        model.selection = [model.manifest.steps[1].id, model.manifest.steps[2].id]
        model.deleteSelection()
        XCTAssertEqual(captions(onDisk), ["a", "c", "d"])
        XCTAssertEqual(model.banner, "Couldn't move Step_03.png to the Trash")
    }

    func testUndoDeleteSkipsStepWhoseFilesLeftTheTrash() throws {
        let model = makeModel()
        model.selection = [model.manifest.steps[0].id]
        model.deleteSelection()
        for item in try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: item)  // "Empty Trash"
        }
        model.undoManager.undo()
        XCTAssertEqual(captions(onDisk), ["b", "c", "d"])
        XCTAssertEqual(model.banner, "Couldn't restore Step_01.png — it's no longer in the Trash")
    }

    func testSaveFailureShowsBannerAndRetries() {
        var fail = true
        let model = makeModel(save: { m, f in if fail { throw CocoaError(.fileWriteUnknown) }; try SessionManifestStore.saveSafely(m, in: f) })
        model.move(fromOffsets: [0], toOffset: 2)
        XCTAssertEqual(model.banner, "Couldn't save changes — will retry")
        XCTAssertEqual(captions(onDisk), ["a", "b", "c", "d"])  // disk untouched
        fail = false
        model.move(fromOffsets: [0], toOffset: 2)
        XCTAssertNil(model.banner)
        XCTAssertEqual(captions(onDisk), captions(model.manifest))
    }

    func testReadOnlyBlocksEdits() throws {
        var m = SessionManifestStore.load(from: folder)
        m.version = SessionManifestStore.currentVersion + 1
        try SessionManifestStore.save(m, in: folder)
        let model = makeModel()
        XCTAssertTrue(model.isReadOnly)
        XCTAssertEqual(model.readOnlyNotice, "Made by a newer version of Clipr — read only")
        model.move(fromOffsets: [0], toOffset: 4)
        model.commitCaption("x", for: model.manifest.steps[0].id)
        model.selection = [model.manifest.steps[0].id]
        model.deleteSelection()
        XCTAssertEqual(captions(model.manifest), ["a", "b", "c", "d"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Step_01.png").path))
    }

    func testReloadPicksUpExternalChangesAndBumpsToken() throws {
        let model = makeModel()
        let before = model.refreshToken
        model.selection = [model.manifest.steps[3].id]
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Step_04.png"))
        model.reload()
        XCTAssertEqual(captions(model.manifest), ["a", "b", "c"])
        XCTAssertTrue(model.selection.isEmpty)
        XCTAssertEqual(model.refreshToken, before + 1)
    }
}
