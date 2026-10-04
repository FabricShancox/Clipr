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

    func testWritesRTFDWithTheStepImage() throws {
        let picture = testImage(width: 40, height: 30) {
            NSColor.systemTeal.set()
            NSRect(x: 0, y: 0, width: 40, height: 30).fill()
        }
        let image = try XCTUnwrap(GuideImages.encode(try XCTUnwrap(picture.bitmap)))
        let doc = GuideDocument(title: "Img", date: Date(), steps: [
            GuideStep(number: 1, caption: "Look", appName: nil, imageSize: .full, image: .file(URL(fileURLWithPath: "/unused.png")), zoom: nil),
        ])
        var images = RenderedImages()
        images.steps[1] = image
        XCTAssertTrue(GuideClipboard.write(html: HTMLGuideWriter.write(doc, images: images, mode: .embedded), to: pasteboard))
        let rtfd = try XCTUnwrap(pasteboard.data(forType: .rtfd))
        let text = try XCTUnwrap(NSAttributedString(rtfd: rtfd, documentAttributes: nil))
        var attachments = 0
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if value != nil { attachments += 1 }
        }
        XCTAssertGreaterThanOrEqual(attachments, 1)
    }
}
