// Tests/ClipprTests/ReviewModelTests.swift
import XCTest
import Cocoa
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

    // M5: a step with its image editor open can't be deleted — the editor would write its
    // sidecar and preview back into the session and break the delete's undo.
    func testDeleteRefusedWhileStepIsInEditor() {
        let model = makeModel()
        let open = model.manifest.steps[1]
        model.stepsInEditor = [open.id]
        model.delete(ids: [open.id, model.manifest.steps[2].id])
        XCTAssertEqual(model.manifest.steps.count, 4)
        XCTAssertEqual(onDisk.steps.count, 4)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(open.file).path))
        XCTAssertEqual(model.banner, ReviewModel.editorOpenBanner)
        XCTAssertFalse(model.undoManager.canUndo)
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
        XCTAssertTrue(model.hasUnsavedChanges)  // what makes closing the window ask first
        XCTAssertEqual(captions(onDisk), ["a", "b", "c", "d"])  // disk untouched
        fail = false
        model.move(fromOffsets: [0], toOffset: 2)
        XCTAssertNil(model.banner)
        XCTAssertFalse(model.hasUnsavedChanges)
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

    /// Attempts every kind of edit and the close/quit flush on a read-only model.
    private func attemptEdits(_ model: ReviewModel) {
        model.move(fromOffsets: [0], toOffset: model.manifest.steps.count)
        if let id = model.manifest.steps.first?.id {
            model.beginCaptionEdit(for: id)
            model.editCaption("typed", for: id)
            model.commitCaption("x", for: id)
            model.selection = [id]
        }
        model.deleteSelection()
        model.flush()
    }

    func testUnknownKindFromNewerVersionOpensReadOnlyAndNeverWrites() throws {
        // A newer Clipr may add step kinds this build can't decode; the full decode fails, but the
        // version still says the file isn't ours to rewrite.
        let json = """
        {"version": 2, "createdAt": "1970-01-01T00:00:00Z", "steps": [
          {"id": "\(UUID().uuidString)", "file": "Step_01.png", "kind": "hover", "caption": "keep me",
           "capturedAt": "1970-01-01T00:00:00Z"}
        ]}
        """
        let url = folder.appendingPathComponent("session.json")
        try Data(json.utf8).write(to: url)
        let before = try Data(contentsOf: url)
        let model = makeModel()
        XCTAssertTrue(model.isReadOnly)
        XCTAssertEqual(model.readOnlyNotice, "Made by a newer version of Clipr — read only")
        attemptEdits(model)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Step_01.png").path))
    }

    func testGarbageManifestOpensReadOnlyAndNeverWrites() throws {
        let url = folder.appendingPathComponent("session.json")
        try Data("{ not json".utf8).write(to: url)
        let before = try Data(contentsOf: url)
        let model = makeModel()
        XCTAssertTrue(model.isReadOnly)
        XCTAssertEqual(model.readOnlyNotice, "Couldn't read session.json — read only")
        // Steps still show, rebuilt from the PNGs.
        XCTAssertEqual(model.manifest.steps.count, 4)
        attemptEdits(model)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testMissingManifestStaysWritable() throws {
        try FileManager.default.removeItem(at: folder.appendingPathComponent("session.json"))
        let model = makeModel()
        XCTAssertFalse(model.isReadOnly)
        XCTAssertNil(model.readOnlyNotice)
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

    func testTypingBackToSavedCaptionDropsPendingEdit() async throws {
        let model = makeModel(captionDelay: 0.05)
        let id = model.manifest.steps[0].id
        model.beginCaptionEdit(for: id)
        model.editCaption("ab", for: id)
        model.editCaption("a", for: id)
        try await Task.sleep(nanoseconds: 200_000_000)
        model.flush()
        XCTAssertEqual(onDisk.steps[0].caption, "a")
    }

    func testTypingBackToEmptyDropsPendingEditForNilCaption() async throws {
        let model = makeModel(captionDelay: 0.05)
        let id = model.manifest.steps[0].id
        model.commitCaption("", for: id)
        XCTAssertNil(onDisk.steps[0].caption)
        model.beginCaptionEdit(for: id)
        model.editCaption("x", for: id)
        model.editCaption("", for: id)
        try await Task.sleep(nanoseconds: 200_000_000)
        model.flush()
        XCTAssertNil(onDisk.steps[0].caption)
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

    func testCancelInOtherStepKeepsPendingCaption() {
        let model = makeModel(captionDelay: 10)
        let a = model.manifest.steps[0].id, b = model.manifest.steps[1].id
        model.beginCaptionEdit(for: a)
        model.editCaption("typed", for: a)
        model.cancelCaptionEdit(for: b)
        XCTAssertEqual(onDisk.steps[0].caption, "typed")
    }

    func testTrashFailureDoesNotOverwriteSaveFailureBanner() {
        let box = Box()
        let flaky = StepFiles(trashItem: { _ in throw CocoaError(.fileWriteNoPermission) },
                              moveItem: { try FileManager.default.moveItem(at: $0, to: $1) })
        let model = ReviewModel(folder: folder, files: flaky,
                                save: { _, _ in if box.fail { throw CocoaError(.fileWriteUnknown) } }, captionDelay: 0.05)
        model.move(fromOffsets: [0], toOffset: 2)  // save fails -> dirty
        model.selection = [model.manifest.steps[0].id]
        model.deleteSelection()
        XCTAssertEqual(model.banner, "Couldn't save changes — will retry")
    }

    func testBeginOnAnotherStepCommitsOpenSession() async throws {
        let model = makeModel(captionDelay: 0.05)
        let a = model.manifest.steps[0].id, b = model.manifest.steps[1].id
        model.beginCaptionEdit(for: a)
        model.editCaption("typed", for: a)
        try await Task.sleep(nanoseconds: 200_000_000)
        model.beginCaptionEdit(for: b)
        XCTAssertEqual(model.undoManager.undoActionName, "Edit Caption")
        model.undoManager.undo()
        XCTAssertEqual(onDisk.steps[0].caption, "a")
        XCTAssertFalse(model.undoManager.canUndo)
    }

    func testCommitSessionForRemovedStepRegistersNoUndo() throws {
        let model = makeModel(captionDelay: 10)
        let id = model.manifest.steps[3].id
        model.beginCaptionEdit(for: id)
        model.selection = [id]
        model.deleteSelection()
        model.undoManager.removeAllActions()
        model.commitCaption("late", for: id)
        XCTAssertFalse(model.undoManager.canUndo)
    }

    func testSkippedReloadRunsAfterNextSuccessfulSave() throws {
        let box = Box()
        let model = makeModel(save: { m, f in if box.fail { throw CocoaError(.fileWriteUnknown) }; try SessionManifestStore.saveSafely(m, in: f) })
        model.move(fromOffsets: [0], toOffset: 2)  // dirty
        try FileManager.default.removeItem(at: folder.appendingPathComponent("Step_04.png"))
        let before = model.refreshToken
        model.reload()  // skipped
        XCTAssertEqual(model.refreshToken, before)
        box.fail = false
        model.flush()
        XCTAssertEqual(model.refreshToken, before + 1)
        XCTAssertEqual(captions(model.manifest), ["b", "a", "c"])
    }

    // MARK: Replace image

    private func setClickData(step index: Int) throws -> UUID {
        var m = SessionManifestStore.load(from: folder)
        m.steps[index].clickPoint = CGPoint(x: 5, y: 6)
        m.steps[index].zoomFile = FilenameGenerator.zoomName(fromStep: m.steps[index].file)
        try SessionManifestStore.save(m, in: folder)
        FileManager.default.createFile(atPath: folder.appendingPathComponent(m.steps[index].zoomFile!).path, contents: Data([9]))
        FileManager.default.createFile(atPath: folder.appendingPathComponent(FilenameGenerator.annotationsName(fromRaw: m.steps[index].file)).path, contents: Data([8]))
        return m.steps[index].id
    }

    private func newImage() -> NSImage {
        testImage(width: 8, height: 5) { NSColor.green.set(); NSRect(x: 0, y: 0, width: 8, height: 5).fill() }
    }

    private func fileData(_ name: String) -> Data? { try? Data(contentsOf: folder.appendingPathComponent(name)) }

    func testReplaceImageWritesNewPNGTrashesOldAndClearsClickData() throws {
        let id = try setClickData(step: 1)
        let model = makeModel()
        model.replaceImage(for: id, with: newImage())
        let step = onDisk.steps[1]
        XCTAssertEqual(step.file, "Step_02.png")
        XCTAssertEqual(step.caption, "b")
        XCTAssertNil(step.clickPoint)
        XCTAssertNil(step.zoomFile)
        XCTAssertEqual(NSImage(contentsOf: folder.appendingPathComponent("Step_02.png"))?.size, CGSize(width: 8, height: 5))
        XCTAssertNil(fileData("Step_02_zoom.png"))
        XCTAssertNil(fileData("Step_02_annotations.json"))
        XCTAssertEqual(model.undoManager.undoActionName, "Replace Image")
    }

    func testUndoRedoReplaceImage() throws {
        let id = try setClickData(step: 1)
        let model = makeModel()
        let before = model.refreshToken
        model.replaceImage(for: id, with: newImage())
        XCTAssertGreaterThan(model.refreshToken, before)
        model.undoManager.undo()
        XCTAssertEqual(fileData("Step_02.png"), Data([1]))
        XCTAssertEqual(fileData("Step_02_zoom.png"), Data([9]))
        XCTAssertEqual(fileData("Step_02_annotations.json"), Data([8]))
        XCTAssertEqual(onDisk.steps[1].clickPoint, CGPoint(x: 5, y: 6))
        XCTAssertEqual(onDisk.steps[1].zoomFile, "Step_02_zoom.png")
        model.undoManager.redo()
        XCTAssertEqual(NSImage(contentsOf: folder.appendingPathComponent("Step_02.png"))?.size, CGSize(width: 8, height: 5))
        XCTAssertNil(onDisk.steps[1].clickPoint)
        XCTAssertNil(fileData("Step_02_zoom.png"))
        model.undoManager.undo()
        XCTAssertEqual(fileData("Step_02.png"), Data([1]))
    }

    func testReplaceImageWriteFailureLeavesOriginal() throws {
        let id = try setClickData(step: 1)
        let model = ReviewModel(folder: folder, files: fakeFiles, writeImage: { _, _ in throw CocoaError(.fileWriteUnknown) }, captionDelay: 0.05)
        model.replaceImage(for: id, with: newImage())
        XCTAssertEqual(fileData("Step_02.png"), Data([1]))
        XCTAssertEqual(fileData("Step_02_zoom.png"), Data([9]))
        XCTAssertEqual(onDisk.steps[1].clickPoint, CGPoint(x: 5, y: 6))
        XCTAssertEqual(model.banner, "Couldn't replace the image for Step_02.png")
        XCTAssertFalse(model.undoManager.canUndo)
    }

    func testReplaceImageBlockedWhenReadOnly() throws {
        var m = SessionManifestStore.load(from: folder)
        m.version = SessionManifestStore.currentVersion + 1
        try SessionManifestStore.save(m, in: folder)
        let before = try Data(contentsOf: folder.appendingPathComponent("session.json"))
        let model = makeModel()
        let manifest = model.manifest
        model.replaceImage(for: model.manifest.steps[0].id, with: newImage())
        XCTAssertEqual(fileData("Step_01.png"), Data([1]))
        XCTAssertEqual(model.manifest, manifest)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("session.json")), before)
        XCTAssertFalse(model.undoManager.canUndo)
    }

    private func trashContents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: trash.path).sorted()
    }
    private func folderContents() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    final class Counter { var trashed = 0 }

    /// Trashes like `fakeFiles`, but refuses any file named `refused` and counts what it moves.
    private func files(refusing refused: String? = nil, counter: Counter = Counter()) -> StepFiles {
        StepFiles(
            trashItem: { [trash] url in
                if url.lastPathComponent == refused { throw CocoaError(.fileWriteNoPermission) }
                counter.trashed += 1
                let dest = trash!.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: dest)
                return dest
            },
            moveItem: { try FileManager.default.moveItem(at: $0, to: $1) }
        )
    }

    private func assertStep2Untouched(_ model: ReviewModel, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(fileData("Step_02.png"), Data([1]), file: file, line: line)
        XCTAssertEqual(fileData("Step_02_zoom.png"), Data([9]), file: file, line: line)
        XCTAssertEqual(fileData("Step_02_annotations.json"), Data([8]), file: file, line: line)
        XCTAssertEqual(onDisk.steps[1].clickPoint, CGPoint(x: 5, y: 6), file: file, line: line)
        XCTAssertEqual(try trashContents(), [], file: file, line: line)
        XCTAssertFalse(try folderContents().contains { $0.contains("replacing") }, "temp file left behind", file: file, line: line)
        XCTAssertFalse(model.undoManager.canUndo, file: file, line: line)
    }

    func testReplaceImageWriteFailureNeverTrashesOriginal() throws {
        let id = try setClickData(step: 1)
        let counter = Counter()
        let model = ReviewModel(folder: folder, files: files(counter: counter), writeImage: { _, _ in throw CocoaError(.fileWriteUnknown) }, captionDelay: 0.05)
        model.replaceImage(for: id, with: newImage())
        XCTAssertEqual(counter.trashed, 0)
        try assertStep2Untouched(model)
        XCTAssertEqual(model.banner, "Couldn't replace the image for Step_02.png")
    }

    func testReplaceImageTrashFailureChangesNothing() throws {
        let id = try setClickData(step: 1)
        let model = ReviewModel(folder: folder, files: files(refusing: "Step_02.png"), captionDelay: 0.05)
        model.replaceImage(for: id, with: newImage())
        try assertStep2Untouched(model)
        XCTAssertEqual(model.banner, "Couldn't replace the image for Step_02.png")
    }

    func testReplaceImageCompanionThatCantBeTrashedChangesNothing() throws {
        let id = try setClickData(step: 1)
        let model = ReviewModel(folder: folder, files: files(refusing: "Step_02_annotations.json"), captionDelay: 0.05)
        model.replaceImage(for: id, with: newImage())
        try assertStep2Untouched(model)
        XCTAssertEqual(model.banner, "Couldn't replace the image for Step_02.png")
    }

    func testUndoReplaceAfterTrashEmptiedKeepsCurrentImage() throws {
        let id = try setClickData(step: 1)
        let counter = Counter()
        let model = ReviewModel(folder: folder, files: files(counter: counter), captionDelay: 0.05)
        model.replaceImage(for: id, with: newImage())
        try emptyTrash()
        counter.trashed = 0
        model.undoManager.undo()
        XCTAssertEqual(counter.trashed, 0)
        XCTAssertEqual(NSImage(contentsOf: folder.appendingPathComponent("Step_02.png"))?.size, CGSize(width: 8, height: 5))
        XCTAssertNil(onDisk.steps[1].clickPoint)
        XCTAssertEqual(try trashContents(), [])  // nothing moved to the Trash
        XCTAssertEqual(model.banner, "Couldn't restore Step_02.png — it's no longer in the Trash")
    }

    func testReplaceImageSaveFailureIsRetriedByFlush() throws {
        let id = try setClickData(step: 1)
        let box = Box()
        box.fail = false
        let model = makeModel(save: { m, f in if box.fail { throw CocoaError(.fileWriteUnknown) }; try SessionManifestStore.saveSafely(m, in: f) })
        box.fail = true
        model.replaceImage(for: id, with: newImage())
        XCTAssertEqual(model.banner, "Couldn't save changes — will retry")
        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(onDisk.steps[1].clickPoint, CGPoint(x: 5, y: 6))
        box.fail = false
        model.flush()
        XCTAssertNil(onDisk.steps[1].clickPoint)
        XCTAssertNil(onDisk.steps[1].zoomFile)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testUndoReplaceAfterStepRemovedByReloadMovesNothing() throws {
        let id = try setClickData(step: 1)
        let model = makeModel()
        model.replaceImage(for: id, with: newImage())
        var m = SessionManifestStore.load(from: folder)
        m.steps.removeAll { $0.id == id }
        try SessionManifestStore.save(m, in: folder)
        model.reload()
        let folderBefore = try folderContents(), trashBefore = try trashContents()
        model.undoManager.undo()
        XCTAssertEqual(try folderContents(), folderBefore)
        XCTAssertEqual(try trashContents(), trashBefore)
        XCTAssertEqual(model.banner, "Couldn't undo — Step_02.png is no longer in this session")
    }

    func testPendingCaptionIsSavedAndKeptAcrossReplace() throws {
        let id = try setClickData(step: 1)
        let model = makeModel(captionDelay: 10)
        model.editCaption("typed", for: id)
        model.replaceImage(for: id, with: newImage())
        XCTAssertEqual(onDisk.steps[1].caption, "typed")
        model.undoManager.undo()  // the replace
        XCTAssertEqual(fileData("Step_02.png"), Data([1]))
        XCTAssertEqual(onDisk.steps[1].caption, "typed")
    }

    func testReplaceRefusedWhileStepIsOpenInEditor() throws {
        let id = try setClickData(step: 1)
        let model = makeModel()
        model.stepsInEditor = [id]
        model.replaceImage(for: id, with: newImage())
        try assertStep2Untouched(model)
        XCTAssertEqual(model.banner, "Close the image editor for this step first")
    }

    /// A refused undo never reaches the undo manager, so both stacks are exactly as they were and
    /// the undo works once the editor is closed.
    func testUndoReplaceRefusedWhileEditorOpenThenWorksAfterClose() throws {
        let id = try setClickData(step: 1)
        let model = makeModel()
        model.replaceImage(for: id, with: newImage())
        model.stepsInEditor = [id]
        model.undo()
        XCTAssertEqual(model.banner, "Close the image editor for this step first")
        XCTAssertEqual(NSImage(contentsOf: folder.appendingPathComponent("Step_02.png"))?.size, CGSize(width: 8, height: 5))
        XCTAssertTrue(model.undoManager.canUndo)
        XCTAssertEqual(model.undoManager.undoActionName, "Replace Image")
        XCTAssertFalse(model.undoManager.canRedo)
        model.stepsInEditor = []
        model.undo()
        XCTAssertEqual(fileData("Step_02.png"), Data([1]))
        XCTAssertEqual(onDisk.steps[1].clickPoint, CGPoint(x: 5, y: 6))
        XCTAssertTrue(model.undoManager.canRedo)
    }

    func testRedoReplaceRefusedWhileEditorOpenStaysRedoable() throws {
        let id = try setClickData(step: 1)
        let model = makeModel()
        model.replaceImage(for: id, with: newImage())
        model.undo()
        model.stepsInEditor = [id]
        model.redo()
        XCTAssertEqual(model.banner, "Close the image editor for this step first")
        XCTAssertEqual(fileData("Step_02.png"), Data([1]))
        XCTAssertTrue(model.undoManager.canRedo)
        XCTAssertEqual(model.undoManager.redoActionName, "Replace Image")
        XCTAssertFalse(model.undoManager.canUndo)
        model.stepsInEditor = []
        model.redo()
        XCTAssertEqual(NSImage(contentsOf: folder.appendingPathComponent("Step_02.png"))?.size, CGSize(width: 8, height: 5))
        XCTAssertTrue(model.undoManager.canUndo)
    }

    /// Only the step being edited is protected: other undos, including another step's image swap,
    /// go ahead while an editor is open.
    func testEditorOnOtherStepDoesNotBlockUndo() throws {
        let id = try setClickData(step: 1)
        let model = makeModel()
        model.replaceImage(for: id, with: newImage())
        model.move(fromOffsets: [0], toOffset: 4)
        model.stepsInEditor = [id]
        model.undo()  // the move: not an image swap
        XCTAssertNil(model.banner)
        XCTAssertEqual(captions(onDisk), ["a", "b", "c", "d"])
        model.undo()  // the replace of the edited step: refused
        XCTAssertEqual(model.banner, "Close the image editor for this step first")
        model.stepsInEditor = [model.manifest.steps[0].id]
        model.undo()  // the replace again, now that a different step is in the editor
        XCTAssertEqual(fileData("Step_02.png"), Data([1]))
        model.redo()
        model.redo()
        XCTAssertEqual(captions(onDisk), ["b", "c", "d", "a"])
        XCTAssertNil(onDisk.steps[0].clickPoint, "step b was re-replaced")
    }

    /// The target tracking survives several swaps of different steps in a row.
    func testRefusalTargetsTheTopSwap() throws {
        let b = try setClickData(step: 1)
        let model = makeModel()
        let c = model.manifest.steps[2].id
        model.replaceImage(for: b, with: newImage())
        model.replaceImage(for: c, with: newImage())
        model.stepsInEditor = [b]
        model.undo()  // c's replace: allowed
        XCTAssertEqual(fileData("Step_03.png"), Data([1]))
        model.undo()  // b's replace: refused
        XCTAssertEqual(model.banner, "Close the image editor for this step first")
        model.stepsInEditor = [c]
        model.redo()  // c again: refused
        XCTAssertEqual(fileData("Step_03.png"), Data([1]))
        model.stepsInEditor = []
        model.undo()
        XCTAssertEqual(fileData("Step_02.png"), Data([1]))
        model.redo()
        model.redo()
        XCTAssertEqual(NSImage(contentsOf: folder.appendingPathComponent("Step_03.png"))?.size, CGSize(width: 8, height: 5))
    }

    /// A Replace-with-File decode can finish after its step was deleted; say so instead of
    /// silently dropping the chosen image.
    func testReplaceImageForRemovedStepShowsBanner() throws {
        let model = makeModel()
        let id = model.manifest.steps[1].id
        model.delete(ids: [id])
        let png = try XCTUnwrap(StepFiles.pngData(newImage()))
        model.replaceImage(for: id, withPNG: png)
        XCTAssertEqual(model.banner, "Couldn't replace the image — that step was removed")
        XCTAssertEqual(model.undoManager.undoActionName, "Delete Steps")
    }

    func testReplaceWithPNGDataWritesItAsIs() throws {
        let id = try setClickData(step: 1)
        let model = makeModel()
        let png = try XCTUnwrap(StepFiles.pngData(newImage()))
        model.replaceImage(for: id, withPNG: png)
        XCTAssertEqual(fileData("Step_02.png"), png)
    }
    // MARK: Image size

    private func sizes(_ m: SessionManifest) -> [ImageSize?] { m.steps.map(\.imageSize) }

    func testSetImageSizeSavesAndUndoRedo() {
        let model = makeModel()
        let ids = model.manifest.steps.map(\.id)
        model.setImageSize(.small, for: [ids[0], ids[2]])
        XCTAssertEqual(sizes(onDisk), [.small, nil, .small, nil])
        XCTAssertEqual(model.undoManager.undoActionName, "Change Image Size")
        model.undoManager.undo()
        XCTAssertEqual(sizes(onDisk), [nil, nil, nil, nil])
        model.undoManager.redo()
        XCTAssertEqual(sizes(onDisk), [.small, nil, .small, nil])
    }

    func testStepImageSizeActsOnSelection() {
        let model = makeModel()
        let ids = model.manifest.steps.map(\.id)
        model.selection = [ids[1]]
        model.stepImageSize(by: -1)
        model.stepImageSize(by: -1)
        XCTAssertEqual(sizes(onDisk), [nil, .medium, nil, nil])
        model.selection = [ids[1], ids[3]]
        model.stepImageSize(by: 1)
        XCTAssertEqual(sizes(onDisk), [nil, .large, nil, nil])
        model.undoManager.undo()
        XCTAssertEqual(sizes(onDisk), [nil, .medium, nil, nil])
        XCTAssertEqual(model.undoManager.undoActionName, "Change Image Size")
    }

    func testImageSizeNoOpRegistersNoUndo() {
        let model = makeModel()
        let id = model.manifest.steps[0].id
        model.setImageSize(.full, for: [id])
        model.setImageSize(nil, for: [id])
        model.selection = [id]
        model.stepImageSize(by: 1)  // already Full
        model.selection = []
        model.stepImageSize(by: -1)  // nothing selected
        model.setImageSize(.small, for: [UUID()])
        XCTAssertFalse(model.undoManager.canUndo)
        XCTAssertEqual(sizes(model.manifest), [nil, nil, nil, nil])
    }

    /// Size undo is field-scoped: it must not roll back a caption saved after the size change.
    func testSizeUndoDoesNotRestoreStaleCaption() async throws {
        let model = makeModel(captionDelay: 0.05)
        let a = model.manifest.steps[0].id
        let b = model.manifest.steps[1].id
        model.beginCaptionEdit(for: a)
        model.editCaption("x", for: a)
        model.commitCaption("x", for: a)
        model.beginCaptionEdit(for: a)
        model.editCaption("xy", for: a)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(onDisk.steps[0].caption, "xy")
        model.setImageSize(.small, for: [b])
        model.commitCaption("xyz", for: a)
        model.undo()  // caption session
        XCTAssertEqual(onDisk.steps[0].caption, "x")
        XCTAssertEqual(onDisk.steps[1].imageSize, .small)
        model.undo()  // size
        XCTAssertEqual(onDisk.steps[0].caption, "x")
        XCTAssertNil(onDisk.steps[1].imageSize)
    }

    /// The scenario as reported: the original caption is "x", so one undo of the final edit and one
    /// of the size land on "x" and nil.
    func testSizeUndoAfterDebouncedCaptionSaveKeepsOriginalCaption() async throws {
        var m = SessionManifestStore.load(from: folder)
        m.steps[0].caption = "x"
        try SessionManifestStore.save(m, in: folder)
        let model = makeModel(captionDelay: 0.05)
        let a = model.manifest.steps[0].id
        let b = model.manifest.steps[1].id
        model.beginCaptionEdit(for: a)
        model.editCaption("xy", for: a)
        try await Task.sleep(nanoseconds: 300_000_000)
        model.setImageSize(.small, for: [b])
        model.commitCaption("xyz", for: a)
        model.undo()
        model.undo()
        XCTAssertEqual(onDisk.steps[0].caption, "x")
        XCTAssertNil(onDisk.steps[1].imageSize)
        model.redo()
        XCTAssertEqual(onDisk.steps[1].imageSize, .small)
        XCTAssertEqual(onDisk.steps[0].caption, "x")
    }

    func testMultiStepSizeUndoRedoThroughUndoRedoEntryPoints() {
        let model = makeModel()
        let ids = model.manifest.steps.map(\.id)
        model.setImageSize(.small, for: [ids[0], ids[2]])
        model.undo()
        XCTAssertEqual(sizes(onDisk), [nil, nil, nil, nil])
        model.redo()
        XCTAssertEqual(sizes(onDisk), [.small, nil, .small, nil])
        model.undo()
        XCTAssertEqual(sizes(onDisk), [nil, nil, nil, nil])
    }

    func testSizeOnUnknownSizeStepRegistersNoUndo() throws {
        let json = """
        {"version":1,"createdAt":"1970-01-01T00:00:00Z","steps":[{"id":"\(UUID().uuidString)","file":"Step_01.png","kind":"click","caption":"a","capturedAt":"1970-01-01T00:00:00Z","imageSize":"huge"}]}
        """
        try Data(json.utf8).write(to: folder.appendingPathComponent("session.json"))
        let model = makeModel()
        model.setImageSize(.full, for: [model.manifest.steps[0].id])
        XCTAssertFalse(model.undoManager.canUndo)
    }

    // MARK: Image swap mirror

    func testFreshActionClearsRedoSoRedoIsInertWithEditorOpen() throws {
        let b = try setClickData(step: 1)
        let model = makeModel()
        model.replaceImage(for: b, with: newImage())
        model.undo()
        model.setImageSize(.small, for: [model.manifest.steps[0].id])
        model.stepsInEditor = [b]
        model.redo()
        XCTAssertNil(model.banner)
        XCTAssertFalse(model.undoManager.canRedo)
        XCTAssertEqual(fileData("Step_02.png"), Data([1]))
    }

    func testFailedSwapUndoThenLaterReplaceRefusalTargetsRightStep() throws {
        let b = try setClickData(step: 1)
        let model = makeModel()
        let c = model.manifest.steps[2].id
        model.replaceImage(for: b, with: newImage())
        for url in try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }
        model.undo()  // trashed original purged: fails, registers nothing
        XCTAssertNotNil(model.banner)
        model.replaceImage(for: c, with: newImage())
        model.stepsInEditor = [c]
        model.undo()
        XCTAssertEqual(model.banner, "Close the image editor for this step first")
        model.stepsInEditor = [b]
        model.undo()  // c's swap is allowed with an editor on b
        XCTAssertEqual(fileData("Step_03.png"), Data([1]))
    }

    func testDeleteUndoInterleavedWithReplaceRefusalTargetsRightStep() throws {
        let b = try setClickData(step: 1)
        let model = makeModel()
        let c = model.manifest.steps[2].id
        model.delete(ids: [c])
        model.undo()
        model.replaceImage(for: b, with: newImage())
        model.stepsInEditor = [c]
        model.undo()  // b's swap: c's editor must not block it
        XCTAssertNil(model.banner)
        XCTAssertEqual(fileData("Step_02.png"), Data([1]))
        model.stepsInEditor = [b]
        model.redo()
        XCTAssertEqual(model.banner, "Close the image editor for this step first")
    }

    func testImageSizeBlockedWhenReadOnly() throws {
        var m = SessionManifestStore.load(from: folder)
        m.version = SessionManifestStore.currentVersion + 1
        try SessionManifestStore.save(m, in: folder)
        let before = try Data(contentsOf: folder.appendingPathComponent("session.json"))
        let model = makeModel()
        let id = model.manifest.steps[0].id
        model.setImageSize(.small, for: [id])
        model.selection = [id]
        model.stepImageSize(by: -1)
        XCTAssertEqual(sizes(model.manifest), [nil, nil, nil, nil])
        XCTAssertFalse(model.undoManager.canUndo)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("session.json")), before)
    }
}
