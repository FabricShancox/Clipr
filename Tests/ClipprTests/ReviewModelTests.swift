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
        XCTAssertEqual(calls, 2)  // Step_02 moved, Step_03 refused
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
        let before = try Data(contentsOf: folder.appendingPathComponent("session.json"))
        let model = makeModel()
        XCTAssertTrue(model.isReadOnly)
        XCTAssertEqual(model.readOnlyNotice, "Made by a newer version of Clipr — read only")
        model.move(fromOffsets: [0], toOffset: 4)
        model.commitCaption("x", for: model.manifest.steps[0].id)
        model.selection = [model.manifest.steps[0].id]
        model.deleteSelection()
        XCTAssertEqual(captions(model.manifest), ["a", "b", "c", "d"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Step_01.png").path))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("session.json")), before)
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

    private func emptyTrash() throws {
        for item in try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: item)
        }
    }

    func testUndoMoveDoesNotResurrectStepDeletedSinceWithTrashEmptied() throws {
        let model = makeModel()
        model.move(fromOffsets: [3], toOffset: 0)  // d a b c
        model.selection = [model.manifest.steps[2].id]  // b
        model.deleteSelection()
        try emptyTrash()
        model.undoManager.undo()  // restore fails, b stays deleted
        model.undoManager.undo()  // undo the move
        XCTAssertEqual(captions(onDisk), ["a", "c", "d"])
        for step in onDisk.steps {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(step.file).path))
        }
    }

    func testUndoMoveKeepsStepAddedByReload() throws {
        let model = makeModel()
        model.move(fromOffsets: [3], toOffset: 0)  // d a b c
        var m = SessionManifestStore.load(from: folder)
        // load() drops entries without an image, so the orphan needs one (created after the load
        // above, which would otherwise adopt it as a caption-less step).
        FileManager.default.createFile(atPath: folder.appendingPathComponent("Step_05.png").path, contents: Data([1]))
        m.steps.append(StepRecord(id: UUID(), file: "Step_05.png", kind: .click, caption: "orphan", clickPoint: nil,
                                  zoomFile: nil, appName: "Safari", capturedAt: Date(timeIntervalSince1970: 0)))
        try SessionManifestStore.save(m, in: folder)
        model.reload()
        model.undoManager.undo()
        XCTAssertEqual(captions(onDisk), ["a", "b", "c", "d", "orphan"])
    }

    final class Box { var fail = true }

    func testReloadKeepsUnsavedEditsAndFlushRetries() {
        let box = Box()
        let model = makeModel(save: { m, f in if box.fail { throw CocoaError(.fileWriteUnknown) }; try SessionManifestStore.saveSafely(m, in: f) })
        model.move(fromOffsets: [0], toOffset: 2)  // b a c d, unsaved
        model.reload()
        XCTAssertEqual(captions(model.manifest), ["b", "a", "c", "d"])
        XCTAssertEqual(model.banner, "Couldn't save changes — will retry")
        box.fail = false
        model.flush()
        XCTAssertEqual(captions(onDisk), ["b", "a", "c", "d"])
        XCTAssertNil(model.banner)
    }

    func testCommitForOtherStepFlushesPendingCaption() {
        let model = makeModel(captionDelay: 10)
        model.editCaption("x", for: model.manifest.steps[0].id)
        model.commitCaption("y", for: model.manifest.steps[1].id)
        XCTAssertEqual(onDisk.steps[0].caption, "x")
        XCTAssertEqual(onDisk.steps[1].caption, "y")
    }

    func testCaptionSessionIsOneUndo() async throws {
        let model = makeModel(captionDelay: 0.05)
        let id = model.manifest.steps[0].id
        model.beginCaptionEdit(for: id)
        for text in ["x", "xy", "xyz"] {
            model.editCaption(text, for: id)
            try await Task.sleep(nanoseconds: 200_000_000)
            XCTAssertEqual(onDisk.steps[0].caption, text)
            XCTAssertFalse(model.undoManager.canUndo)
        }
        model.commitCaption("xyz", for: id)
        XCTAssertEqual(model.undoManager.undoActionName, "Edit Caption")
        model.undoManager.undo()
        XCTAssertEqual(onDisk.steps[0].caption, "a")
        XCTAssertFalse(model.undoManager.canUndo)
    }

    func testCancelCaptionEditRestoresOriginalWithoutUndo() async throws {
        let model = makeModel(captionDelay: 0.05)
        let id = model.manifest.steps[0].id
        model.beginCaptionEdit(for: id)
        model.editCaption("typed", for: id)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(onDisk.steps[0].caption, "typed")
        model.cancelCaptionEdit(for: id)
        XCTAssertEqual(onDisk.steps[0].caption, "a")
        XCTAssertFalse(model.undoManager.canUndo)
    }

    func testSaveFailureBannerSurvivesTrashFailureBanner() {
        let box = Box()
        let flaky = StepFiles(
            trashItem: { [trash] url in
                if url.lastPathComponent == "Step_03.png" { throw CocoaError(.fileWriteNoPermission) }
                let dest = trash!.appendingPathComponent(UUID().uuidString)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) }
        )
        let model = ReviewModel(folder: folder, files: flaky,
                                save: { _, _ in if box.fail { throw CocoaError(.fileWriteUnknown) } }, captionDelay: 0.05)
        model.selection = [model.manifest.steps[1].id, model.manifest.steps[2].id]
        model.deleteSelection()
        XCTAssertEqual(model.banner, "Couldn't save changes — will retry")
    }

    func testDeleteOfUnknownIDsLeavesBannerAlone() {
        let box = Box()
        let model = makeModel(save: { _, _ in if box.fail { throw CocoaError(.fileWriteUnknown) } })
        model.move(fromOffsets: [0], toOffset: 2)
        model.delete(ids: [UUID()])
        XCTAssertEqual(model.banner, "Couldn't save changes — will retry")
    }

    func testRestoreWithNothingRestoredSavesNothingAndRegistersNoRedo() throws {
        let model = makeModel()
        model.selection = [model.manifest.steps[0].id]
        model.deleteSelection()
        try emptyTrash()
        model.undoManager.undo()
        XCTAssertFalse(model.undoManager.canRedo)
        XCTAssertEqual(captions(onDisk), ["b", "c", "d"])
    }
}
