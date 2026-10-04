// Tests/ClipprTests/GuideClipboardTests.swift
import XCTest
import Cocoa
@testable import Clipr

@MainActor
final class GuideClipboardTests: XCTestCase {
    var pasteboard: NSPasteboard!

    override func setUp() async throws {
        // A private pasteboard, so the tests never touch what the user has copied.
        pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipprTests.\(UUID().uuidString)"))
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    private var html: String {
        let doc = GuideDocument(title: "Clip test", date: Date(), steps: [
            GuideStep(number: 1, caption: "Click **Save** now", appName: "Safari", imageSize: .full, image: .missing, zoom: nil),
        ])
        return HTMLGuideWriter.write(doc, images: RenderedImages(), mode: .embedded)
    }

    func testWritesHTMLAndRTF() throws {
        XCTAssertTrue(GuideClipboard.write(html: html, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .html), html)
        let rtf = try XCTUnwrap(pasteboard.data(forType: .rtf))
        let text = try XCTUnwrap(NSAttributedString(rtf: rtf, documentAttributes: nil))
        XCTAssertTrue(text.string.contains("Clip test"))
        XCTAssertTrue(text.string.contains("Click Save now"))
    }

    func testRTFKeepsBold() throws {
        let rtf = try XCTUnwrap(GuideClipboard.rtfData(fromHTML: html))
        let text = try XCTUnwrap(NSAttributedString(rtf: rtf, documentAttributes: nil))
        let range = (text.string as NSString).range(of: "Save")
        XCTAssertNotEqual(range.location, NSNotFound)
        let font = try XCTUnwrap(text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testReplacesWhatWasOnThePasteboard() {
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        GuideClipboard.write(html: html, to: pasteboard)
        // The pasteboard may derive plain text from the RTF, but the old string must be gone.
        XCTAssertNotEqual(pasteboard.string(forType: .string), "old")
    }
}
