// Tests/ClipprTests/ManifestEditorTests.swift
import XCTest
@testable import Clipr

final class ManifestEditorTests: XCTestCase {
    private func manifest(_ names: [String]) -> SessionManifest {
        SessionManifest(createdAt: Date(timeIntervalSince1970: 0), steps: names.map {
            StepRecord(id: UUID(), file: "\($0).png", kind: .click, caption: $0, clickPoint: nil,
                       zoomFile: nil, appName: nil, capturedAt: Date(timeIntervalSince1970: 0))
        })
    }
    private func files(_ m: SessionManifest) -> [String] { m.steps.map { String($0.file.dropLast(4)) } }

    func testMoveSingleUpAndDown() {
        let m = manifest(["a", "b", "c", "d"])
        XCTAssertEqual(files(ManifestEditor.moving(m, fromOffsets: [2], toOffset: 0)), ["c", "a", "b", "d"])
        XCTAssertEqual(files(ManifestEditor.moving(m, fromOffsets: [0], toOffset: 4)), ["b", "c", "d", "a"])
        XCTAssertEqual(files(ManifestEditor.moving(m, fromOffsets: [1], toOffset: 3)), ["a", "c", "b", "d"])
    }

    func testMoveNonContiguousToEnd() {
        let m = manifest(["a", "b", "c", "d", "e"])
        XCTAssertEqual(files(ManifestEditor.moving(m, fromOffsets: [0, 2], toOffset: 5)), ["b", "d", "e", "a", "c"])
    }

    func testMoveNonContiguousToMiddle() {
        let m = manifest(["a", "b", "c", "d", "e"])
        XCTAssertEqual(files(ManifestEditor.moving(m, fromOffsets: [0, 4], toOffset: 2)), ["b", "a", "e", "c", "d"])
    }

    func testMoveOutOfRangeIsNoOp() {
        let m = manifest(["a", "b"])
        XCTAssertEqual(ManifestEditor.moving(m, fromOffsets: [5], toOffset: 0), m)
        XCTAssertEqual(ManifestEditor.moving(m, fromOffsets: [0], toOffset: 9), m)
        XCTAssertEqual(ManifestEditor.moving(m, fromOffsets: [], toOffset: 0), m)
    }

    func testSettingCaptionTrimsAndClears() {
        let m = manifest(["a", "b"])
        let id = m.steps[1].id
        XCTAssertEqual(ManifestEditor.settingCaption("  Click **Save**  ", forStep: id, in: m).steps[1].caption, "Click **Save**")
        XCTAssertNil(ManifestEditor.settingCaption("   ", forStep: id, in: m).steps[1].caption)
        XCTAssertNil(ManifestEditor.settingCaption(nil, forStep: id, in: m).steps[1].caption)
        XCTAssertEqual(ManifestEditor.settingCaption("x", forStep: UUID(), in: m), m)  // unknown id
    }

    func testRemoveThenRestoreInterleaved() {
        let m = manifest(["a", "b", "c", "d", "e"])
        let ids: Set<UUID> = [m.steps[1].id, m.steps[3].id, m.steps[4].id]
        let (removedManifest, removed) = ManifestEditor.removing(ids: ids, from: m)
        XCTAssertEqual(files(removedManifest), ["a", "c"])
        XCTAssertEqual(removed.map(\.index), [1, 3, 4])
        XCTAssertEqual(ManifestEditor.restoring(removed, into: removedManifest), m)
    }

    func testRestoreClampsToEnd() {
        let m = manifest(["a", "b", "c"])
        let (shrunk, removed) = ManifestEditor.removing(ids: [m.steps[2].id], from: m)
        let shorter = ManifestEditor.removing(ids: [shrunk.steps[0].id], from: shrunk).0  // now just ["b"]
        XCTAssertEqual(files(ManifestEditor.restoring(removed, into: shorter)), ["b", "c"])
    }
}
