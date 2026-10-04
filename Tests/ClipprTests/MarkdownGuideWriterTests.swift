// Tests/ClipprTests/MarkdownGuideWriterTests.swift
import XCTest
@testable import Clipr

final class MarkdownGuideWriterTests: XCTestCase {
    var folder: URL!
    let date = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!
    let png = GuideImage(data: Data([0x89, 0x50, 1]), pixelWidth: 10, pixelHeight: 5, kind: .png)
    let jpeg = GuideImage(data: Data([0xFF, 0xD8, 2]), pixelWidth: 10, pixelHeight: 5, kind: .jpeg)
    let somewhere = GuideImageRef.file(URL(fileURLWithPath: "/unused.png"))

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var doc: GuideDocument {
        GuideDocument(title: "Set up VPN", date: date, steps: [
            GuideStep(number: 1, caption: "Click **Save** in Safari", appName: "Safari", imageSize: .full, image: somewhere, zoom: somewhere),
            GuideStep(number: 2, caption: "Click in **Warp**", appName: nil, imageSize: .medium, image: somewhere, zoom: nil),
            GuideStep(number: 3, caption: nil, appName: nil, imageSize: .small, image: .missing, zoom: nil),
        ])
    }

    private var images: RenderedImages { RenderedImages(steps: [1: png, 2: jpeg], zooms: [1: png]) }

    func testDocumentLayout() {
        XCTAssertEqual(MarkdownGuideWriter.write(doc, images: images), """
        # Set up VPN
        _4 Oct 2026 · 3 steps_

        ## 1. Click **Save** in Safari
        ![Step 1](images/step-01.png)

        ![Step 1 close-up](images/step-01-zoom.png)

        ## 2. Click in **Warp**
        <img src="images/step-02.jpg" alt="Step 2" width="60%">

        ## 3. Step 3
        _Image unavailable_

        """)
    }

    func testMultiLineCaptionStaysInHeading() {
        let multi = GuideDocument(title: "T", date: date, steps: [
            GuideStep(number: 1, caption: "Click **Save**\n# not a heading", appName: nil, imageSize: .full, image: somewhere, zoom: nil),
        ])
        let lines = MarkdownGuideWriter.write(multi, images: images).components(separatedBy: "\n")
        XCTAssertEqual(lines[3], "## 1. Click **Save** \\# not a heading")
        XCTAssertEqual(lines[4], "![Step 1](images/step-01.png)")
    }

    func testTitleIsEscaped() {
        let titled = GuideDocument(title: "[Draft] <b>", date: date, steps: [])
        XCTAssertTrue(MarkdownGuideWriter.write(titled, images: RenderedImages()).hasPrefix("# \\[Draft\\] \\<b\\>\n"))
    }

    func testExportWritesGuideAndPositionalImages() throws {
        try MarkdownGuideWriter.export(doc, images: images, to: folder)
        let guide = try String(contentsOf: folder.appendingPathComponent("guide.md"), encoding: .utf8)
        XCTAssertEqual(guide, MarkdownGuideWriter.write(doc, images: images))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("images").path).sorted()
        XCTAssertEqual(names, ["step-01-zoom.png", "step-01.png", "step-02.jpg"])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("images/step-02.jpg")), jpeg.data)
    }

    func testHasExistingGuide() throws {
        XCTAssertFalse(MarkdownGuideWriter.hasExistingGuide(in: folder))
        try MarkdownGuideWriter.export(doc, images: images, to: folder)
        XCTAssertTrue(MarkdownGuideWriter.hasExistingGuide(in: folder))
        let other = folder.appendingPathComponent("other")
        try? FileManager.default.createDirectory(at: other.appendingPathComponent("images"), withIntermediateDirectories: true)
        XCTAssertTrue(MarkdownGuideWriter.hasExistingGuide(in: other), "an images folder alone also needs the Replace prompt")
    }

    func testFailedCloseUpIsOmitted() {
        let step = GuideStep(number: 1, caption: "A", appName: nil, imageSize: .full,
                             image: .file(URL(fileURLWithPath: "/unused.png")), zoom: .file(URL(fileURLWithPath: "/unused-zoom.png")))
        let image = GuideImage(data: Data([1]), pixelWidth: 10, pixelHeight: 5, kind: .png)
        let md = MarkdownGuideWriter.write(GuideDocument(title: "T", date: Date(), steps: [step]),
                                           images: RenderedImages(steps: [1: image]))
        XCTAssertFalse(md.contains("close-up"))
        XCTAssertFalse(md.contains("unavailable"))
    }
}
