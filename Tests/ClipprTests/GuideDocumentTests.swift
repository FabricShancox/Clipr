// Tests/ClipprTests/GuideDocumentTests.swift
import XCTest
@testable import Clipr

final class GuideDocumentTests: XCTestCase {
    var folder: URL!
    var manifest: SessionManifest!
    let created = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Session_2026-10-04_09-30-00")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["Step_01.png", "Step_02.png", "Step_02_zoom.png"] {
            FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data([1]))
        }
        // Step_03.png is deliberately not created: that step's image is missing.
        manifest = SessionManifest(createdAt: created, steps: [
            step("Step_01.png", caption: "Click **Save**", app: "Safari", size: nil),
            step("Step_02.png", caption: "   ", app: " ", size: .small, zoom: "Step_02_zoom.png"),
            step("Step_03.png", caption: nil, app: nil, size: .large, zoom: "Step_03_zoom.png"),
        ])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    private func step(_ file: String, caption: String?, app: String?, size: ImageSize?, zoom: String? = nil) -> StepRecord {
        StepRecord(id: UUID(), file: file, kind: .click, caption: caption, clickPoint: nil,
                   zoomFile: zoom, appName: app, capturedAt: created, imageSize: size)
    }

    private func make(selection: Set<UUID> = [], includeZoom: Bool = false, title: String = "Guide") -> GuideDocument {
        GuideDocument.make(manifest: manifest, folder: folder, selection: selection,
                           options: ExportOptions(title: title, includeZoom: includeZoom))
    }

    func testAllStepsWhenNothingSelected() {
        let doc = make()
        XCTAssertEqual(doc.steps.map(\.number), [1, 2, 3])
        XCTAssertEqual(doc.steps.map(\.caption), ["Click **Save**", nil, nil])
        XCTAssertEqual(doc.steps.map(\.appName), ["Safari", nil, nil])
        XCTAssertEqual(doc.date, created)
    }

    func testSelectionKeepsReviewOrderAndRenumbers() {
        let ids = manifest.steps.map(\.id)
        let doc = make(selection: [ids[2], ids[0]])
        XCTAssertEqual(doc.steps.map(\.number), [1, 2])
        XCTAssertEqual(doc.steps.map(\.caption), ["Click **Save**", nil])
        XCTAssertEqual(doc.steps[1].image, .missing)
    }

    func testStaleSelectionFallsBackToAllSteps() {
        let doc = make(selection: [UUID()])
        XCTAssertEqual(doc.steps.count, 3)
    }

    func testPartiallyStaleSelectionExportsOnlyLiveSteps() {
        let ids = manifest.steps.map(\.id)
        let doc = make(selection: [ids[1], UUID()])
        XCTAssertEqual(doc.steps.map(\.number), [1])
        XCTAssertEqual(doc.steps[0].image, .file(folder.appendingPathComponent("Step_02.png")))
    }

    func testSizesWithNilMeaningFull() {
        XCTAssertEqual(make().steps.map(\.imageSize), [.full, .small, .large])
        XCTAssertEqual(ImageSize.allCases.map(\.widthPercent), [40, 60, 80, 100])
    }

    func testZoomOnlyWhenIncludedAndOnDisk() {
        XCTAssertEqual(make().steps.map(\.zoom), [nil, nil, nil])
        let zoomed = make(includeZoom: true)
        XCTAssertEqual(zoomed.steps[0].zoom, nil)
        XCTAssertEqual(zoomed.steps[1].zoom, .file(folder.appendingPathComponent("Step_02_zoom.png")))
        XCTAssertEqual(zoomed.steps[2].zoom, nil, "a close-up whose file is gone is left out")
    }

    func testMissingImageBecomesMissingRef() {
        let doc = make()
        XCTAssertEqual(doc.steps[0].image, .file(folder.appendingPathComponent("Step_01.png")))
        XCTAssertEqual(doc.steps[2].image, .missing)
    }

    func testTitleIsTrimmedAndDefaultsToFolderName() {
        XCTAssertEqual(make(title: "  Set up VPN \n now ").title, "Set up VPN   now")
        XCTAssertEqual(make(title: "   ").title, "Session_2026-10-04_09-30-00")
    }

    func testSubtitle() {
        XCTAssertEqual(GuideDocument.dateText(created, timeZone: TimeZone(identifier: "UTC")!), "4 Oct 2026")
        // The subtitle uses the current time zone, so the expected date does too.
        let day = GuideDocument.dateText(created)
        XCTAssertEqual(make().subtitle, "\(day) · 3 steps")
        XCTAssertEqual(make(selection: [manifest.steps[0].id]).subtitle, "\(day) · 1 step")
    }

    func testSuggestedFileNames() {
        XCTAssertEqual(GuideFormat.pdf.suggestedFileName(for: "Set up / VPN"), "Set up - VPN.pdf")
        XCTAssertEqual(GuideFormat.html.suggestedFileName(for: "  "), "Guide.html")
        XCTAssertEqual(GuideFormat.gif.suggestedFileName(for: "Demo"), "Demo.gif")
        XCTAssertEqual(GuideFormat.pdf.suggestedFileName(for: "A\u{202E}B\u{2066}C\u{2069}"), "ABC.pdf")
        XCTAssertEqual(GuideFormat.markdown.suggestedFileName(for: "Demo"), "Demo")
    }

    func testPositionalImageNames() {
        XCTAssertEqual(GuideImage.fileName(step: 1, zoom: false, kind: .png), "step-01.png")
        XCTAssertEqual(GuideImage.fileName(step: 12, zoom: true, kind: .jpeg), "step-12-zoom.jpg")
        XCTAssertEqual(GuideImage.fileName(step: 100, zoom: false, kind: .png), "step-100.png")
    }
}
