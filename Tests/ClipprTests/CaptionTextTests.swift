// Tests/ClipprTests/CaptionTextTests.swift
import XCTest
@testable import Clipr

final class CaptionTextTests: XCTestCase {
    private func hasURL(_ text: AttributedString) -> Bool {
        text.runs.contains { $0.link != nil || $0.imageURL != nil }
    }

    func testMarkdownLinkLosesItsLink() {
        let text = CaptionText.rendered("[Open](https://evil.example)")
        XCTAssertFalse(hasURL(text))
        XCTAssertEqual(String(text.characters), "Open")
    }

    func testAutolinkLosesItsLink() {
        XCTAssertFalse(hasURL(CaptionText.rendered("<https://x.example>")))
    }

    func testEmphasisIsKept() {
        let text = CaptionText.rendered("Click **Save**")
        XCTAssertEqual(String(text.characters), "Click Save")
        let save = text.runs.first { String(text[$0.range].characters) == "Save" }
        XCTAssertEqual(save?.inlinePresentationIntent, .stronglyEmphasized)
    }

    func testImageLosesItsURL() {
        XCTAssertFalse(hasURL(CaptionText.rendered("![a](file:///x)")))
    }

    func testMalformedMarkdownStaysReadable() {
        XCTAssertEqual(String(CaptionText.rendered("a [b](c").characters).contains("b"), true)
    }
}
