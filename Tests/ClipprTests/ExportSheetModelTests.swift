// Tests/ClipprTests/ExportSheetModelTests.swift
import XCTest
@testable import Clipr

@MainActor
final class ExportSheetModelTests: XCTestCase {
    var defaults: UserDefaults!
    var settings: SettingsStore!
    var folder: URL!
    var manifest: SessionManifest!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "ClipprTests.\(UUID().uuidString)")
        settings = SettingsStore(defaults: defaults)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Session_2026-10-04_09-30-00")
        let steps = (1...3).map { index in
            StepRecord(id: UUID(), file: String(format: "Step_%02d.png", index), kind: .click, caption: "Step \(index)",
                       clickPoint: nil, zoomFile: nil, appName: nil, capturedAt: Date(timeIntervalSince1970: 0))
        }
        manifest = SessionManifest(createdAt: Date(timeIntervalSince1970: 0), steps: steps)
    }

    private func model(selection: Set<UUID> = []) -> ExportSheetModel {
        ExportSheetModel(manifest: manifest, folder: folder, selection: selection, settings: settings)
    }

    func testDefaultsWithoutSelection() {
        let model = model()
        XCTAssertEqual(model.options, ExportOptions(format: .pdf, title: "Session_2026-10-04_09-30-00", includeZoom: false, gifFrameSeconds: 2))
        XCTAssertEqual(model.selectionCount, 0)
        XCTAssertFalse(model.useSelection)
        XCTAssertEqual(model.stepCount, 3)
        XCTAssertTrue(model.canExport)
        XCTAssertEqual(model.makeDocument().steps.count, 3)
    }

    func testSelectionIsOfferedAndUsedByDefault() {
        let model = model(selection: [manifest.steps[2].id, UUID()])
        XCTAssertEqual(model.selectionCount, 1, "ids no longer in the session don't count")
        XCTAssertTrue(model.useSelection)
        XCTAssertEqual(model.makeDocument().steps.map(\.caption), ["Step 3"])
        model.useSelection = false
        XCTAssertEqual(model.stepCount, 3)
        XCTAssertEqual(model.makeDocument().steps.count, 3)
    }

    func testRemembersOptionsButNotTitle() {
        let first = model()
        first.options.format = .gif
        first.options.includeZoom = true
        first.options.gifFrameSeconds = 3.5
        first.options.title = "Custom"
        first.rememberOptions()
        XCTAssertEqual(model().options, ExportOptions(format: .gif, title: "Session_2026-10-04_09-30-00", includeZoom: true, gifFrameSeconds: 3.5))
    }

    func testCopyActionAndWebAppNote() {
        let model = model()
        XCTAssertEqual(model.actionTitle, "Export…")
        XCTAssertFalse(model.showsWebAppNote)
        model.options.format = .clipboard
        XCTAssertEqual(model.actionTitle, "Copy")
        XCTAssertEqual(model.showsWebAppNote, GuideClipboard.imagesMayBeDropped)
    }

    func testNothingToExportWithEmptySession() {
        manifest.steps = []
        XCTAssertFalse(model().canExport)
    }
}
