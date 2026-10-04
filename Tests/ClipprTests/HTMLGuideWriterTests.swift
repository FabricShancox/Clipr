// Tests/ClipprTests/HTMLGuideWriterTests.swift
import XCTest
@testable import Clipr

final class HTMLGuideWriterTests: XCTestCase {
    let date = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!
    let png = GuideImage(data: Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]), pixelWidth: 10, pixelHeight: 5, kind: .png)
    let zoomJPEG = GuideImage(data: Data([0xFF, 0xD8, 9]), pixelWidth: 4, pixelHeight: 4, kind: .jpeg)
    let somewhere = GuideImageRef.file(URL(fileURLWithPath: "/unused.png"))

    private func doc(title: String = "My Guide", captions: [String?] = ["Heading A", "Heading B", nil],
                     app: String? = "Safari") -> GuideDocument {
        let sizes: [ImageSize] = [.full, .medium, .small]
        let steps = captions.enumerated().map { index, caption in
            GuideStep(number: index + 1, caption: caption, appName: app, imageSize: sizes[index % 3],
                      image: somewhere, zoom: index == 0 ? somewhere : nil)
        }
        return GuideDocument(title: title, date: date, steps: steps)
    }

    /// Step 1 and 2 rendered, step 3's image missing; step 1 has a close-up.
    private var images: RenderedImages {
        RenderedImages(steps: [1: png, 2: png], zooms: [1: zoomJPEG])
    }

    func testHeaderHasTitleDateAndCount() {
        let html = HTMLGuideWriter.write(doc(), images: images, mode: .embedded)
        XCTAssertTrue(html.contains("<title>My Guide</title>"))
        XCTAssertTrue(html.contains("<h1>My Guide</h1>"))
        XCTAssertTrue(html.contains("<p class=\"meta\">4 Oct 2026 · 3 steps</p>"))
    }

    func testStepsInOrderWithNumbersAndFallbackHeading() throws {
        let html = HTMLGuideWriter.write(doc(), images: images, mode: .embedded)
        let a = try XCTUnwrap(html.range(of: "<span class=\"num\">1</span><span class=\"caption\">Heading A</span>"))
        let b = try XCTUnwrap(html.range(of: "<span class=\"num\">2</span><span class=\"caption\">Heading B</span>"))
        let c = try XCTUnwrap(html.range(of: "<span class=\"num\">3</span><span class=\"caption\">Step 3</span>"))
        XCTAssertLessThan(a.lowerBound, b.lowerBound)
        XCTAssertLessThan(b.lowerBound, c.lowerBound)
        XCTAssertTrue(html.contains("<p class=\"app\">Safari</p>"))
    }

    func testWidthFollowsImageSize() {
        let html = HTMLGuideWriter.write(doc(), images: images, mode: .embedded)
        XCTAssertTrue(html.contains("alt=\"Step 1\" style=\"width:100%\""))
        XCTAssertTrue(html.contains("alt=\"Step 2\" style=\"width:60%\""))
        XCTAssertTrue(html.contains("<div class=\"shot missing\" style=\"width:40%\">Image unavailable</div>"))
    }

    func testEmbeddedImagesAreDataURIs() {
        let html = HTMLGuideWriter.write(doc(), images: images, mode: .embedded)
        XCTAssertTrue(html.contains("src=\"data:image/png;base64,\(png.data.base64EncodedString())\""))
        XCTAssertTrue(html.contains("src=\"data:image/jpeg;base64,\(zoomJPEG.data.base64EncodedString())\""))
    }

    func testLinkedImagesUsePositionalPaths() {
        let html = HTMLGuideWriter.write(doc(), images: images, mode: .linked(prefix: "images/"))
        XCTAssertTrue(html.contains("<img class=\"shot\" src=\"images/step-01.png\" alt=\"Step 1\""))
        XCTAssertTrue(html.contains("<img class=\"zoom\" src=\"images/step-01-zoom.jpg\" alt=\"Step 1 close-up\" style=\"width:30%\">"))
        XCTAssertFalse(html.contains("data:"))
    }

    func testCloseUpOnlyForStepsThatHaveOne() {
        let html = HTMLGuideWriter.write(doc(), images: images, mode: .embedded)
        XCTAssertTrue(html.contains("alt=\"Step 1 close-up\""))
        XCTAssertFalse(html.contains("alt=\"Step 2 close-up\""))
    }

    func testStepsAvoidPageBreaks() {
        XCTAssertTrue(HTMLGuideWriter.css.contains(".step { break-inside: avoid; page-break-inside: avoid;"))
    }

    func testHostileCaptionsProduceNoActiveContent() {
        let hostile = doc(
            title: "<script>alert('t')</script>",
            captions: ["<script>alert(1)</script>", "[x](javascript:alert(1))", "<img src=x onerror=alert(1)>"],
            app: "\"><svg onload=alert(1)>"
        )
        for mode in [HTMLImageMode.embedded, .linked(prefix: "\"><script>")] {
            let html = HTMLGuideWriter.write(hostile, images: images, mode: mode).lowercased()
            XCTAssertFalse(html.contains("<script"), "\(mode)")
            XCTAssertFalse(html.contains("<svg"), "\(mode)")
            let activeAttribute = try! NSRegularExpression(pattern: "<[^>]*(\\son[a-z]+\\s*=|javascript:)[^>]*>")
            XCTAssertNil(activeAttribute.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), "\(mode)")
        }
    }
}
