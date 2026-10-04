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
    // MARK: Image size

    func testSettingImageSizeSingleAndMulti() {
        let m = manifest(["a", "b", "c"])
        let one = ManifestEditor.settingImageSize(.small, forSteps: [m.steps[1].id], in: m)
        XCTAssertEqual(one.steps.map(\.imageSize), [nil, .small, nil])
        let two = ManifestEditor.settingImageSize(.medium, forSteps: [m.steps[0].id, m.steps[2].id], in: one)
        XCTAssertEqual(two.steps.map(\.imageSize), [.medium, .small, .medium])
    }

    /// Full is stored as nil, the same as a step that was never sized, so "set to Full" on such a
    /// step is no change at all.
    func testSettingFullStoresNil() {
        let m = manifest(["a"])
        let id = m.steps[0].id
        XCTAssertEqual(ManifestEditor.settingImageSize(.full, forSteps: [id], in: m), m)
        let small = ManifestEditor.settingImageSize(.small, forSteps: [id], in: m)
        XCTAssertNil(ManifestEditor.settingImageSize(.full, forSteps: [id], in: small).steps[0].imageSize)
        XCTAssertNil(ManifestEditor.settingImageSize(nil, forSteps: [id], in: small).steps[0].imageSize)
    }

    func testImageSizeUnknownIDIsNoOp() {
        let m = manifest(["a", "b"])
        XCTAssertEqual(ManifestEditor.settingImageSize(.small, forSteps: [UUID()], in: m), m)
        XCTAssertEqual(ManifestEditor.steppingImageSize(by: -1, forSteps: [UUID()], in: m), m)
        XCTAssertEqual(ManifestEditor.settingImageSize(.small, forSteps: [], in: m), m)
    }

    func testSteppingImageSizeTreatsNilAsFullAndClamps() {
        let m = manifest(["a"])
        let id = m.steps[0].id
        XCTAssertEqual(ManifestEditor.steppingImageSize(by: 1, forSteps: [id], in: m), m, "Full can't grow")
        var sizes: [ImageSize?] = []
        var current = m
        for _ in 0..<4 {
            current = ManifestEditor.steppingImageSize(by: -1, forSteps: [id], in: current)
            sizes.append(current.steps[0].imageSize)
        }
        XCTAssertEqual(sizes, [.large, .medium, .small, .small])
        XCTAssertEqual(ManifestEditor.steppingImageSize(by: 1, forSteps: [id], in: current).steps[0].imageSize, .medium)
        let large = ManifestEditor.settingImageSize(.large, forSteps: [id], in: m)
        XCTAssertNil(ManifestEditor.steppingImageSize(by: 1, forSteps: [id], in: large).steps[0].imageSize, "back to Full is nil")
        XCTAssertEqual(ManifestEditor.steppingImageSize(by: -9, forSteps: [id], in: m).steps[0].imageSize, .small)
    }

    func testSteppingImageSizeMovesEachSelectedStepFromItsOwnSize() {
        let m = manifest(["a", "b", "c"])
        let sized = ManifestEditor.settingImageSize(.small, forSteps: [m.steps[0].id], in: m)
        let stepped = ManifestEditor.steppingImageSize(by: -1, forSteps: [m.steps[0].id, m.steps[1].id], in: sized)
        XCTAssertEqual(stepped.steps.map(\.imageSize), [.small, .large, nil])
    }
}
