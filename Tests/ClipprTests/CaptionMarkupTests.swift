// Tests/ClipprTests/CaptionMarkupTests.swift
import XCTest
@testable import Clipr

final class CaptionMarkupTests: XCTestCase {
    func testHTMLKeepsBoldItalicAndCode() {
        XCTAssertEqual(
            CaptionMarkup.html("Click **Save** in *Safari*, run `ls`", fallbackNumber: 1),
            "Click <strong>Save</strong> in <em>Safari</em>, run <code>ls</code>"
        )
    }

    func testHTMLStripsLinksImagesAndAutolinksToText() {
        XCTAssertEqual(
            CaptionMarkup.html("See [docs](https://x.com) and ![pic](a.png) <https://evil.com>", fallbackNumber: 1),
            "See docs and pic https://evil.com"
        )
        XCTAssertEqual(CaptionMarkup.html("[x](javascript:alert(1))", fallbackNumber: 1), "x")
    }

    func testHTMLDropsRawTagsAndEscapesText() {
        XCTAssertEqual(
            CaptionMarkup.html("<script>alert(1)</script> & \"q\" 'a'", fallbackNumber: 1),
            "alert(1) &amp; &quot;q&quot; &#39;a&#39;"
        )
        XCTAssertEqual(CaptionMarkup.html("Press <b>Enter</b>", fallbackNumber: 1), "Press Enter")
        XCTAssertEqual(CaptionMarkup.html("**a<b**", fallbackNumber: 1), "<strong>a&lt;b</strong>")
    }

    func testEmptyCaptionsFallBackToStepNumber() {
        for caption in [nil, "", "   ", "<br>", "**<b>**"] as [String?] {
            XCTAssertEqual(CaptionMarkup.html(caption, fallbackNumber: 4), "Step 4", "\(String(describing: caption))")
            XCTAssertEqual(CaptionMarkup.markdown(caption, fallbackNumber: 4), "Step 4")
            XCTAssertEqual(CaptionMarkup.plainText(caption, fallbackNumber: 4), "Step 4")
        }
    }

    func testNewlinesCollapseToSpaces() {
        XCTAssertEqual(CaptionMarkup.html("line1\nline2\r\nline3", fallbackNumber: 1), "line1 line2 line3")
        XCTAssertEqual(CaptionMarkup.markdown("line1\nline2", fallbackNumber: 1), "line1 line2")
    }

    func testMarkdownKeepsEmphasis() {
        XCTAssertEqual(CaptionMarkup.markdown("Click **Save** in *Safari*", fallbackNumber: 1), "Click **Save** in *Safari*")
        XCTAssertEqual(CaptionMarkup.markdown("***both***", fallbackNumber: 1), "***both***")
    }

    func testMarkdownReducesLinksImagesAndHTMLToText() {
        XCTAssertEqual(CaptionMarkup.markdown("[docs](https://x.com) ![pic](a.png) <b>hi</b>", fallbackNumber: 1), "docs pic hi")
    }

    func testMarkdownEscapesSyntaxCharacters() {
        XCTAssertEqual(CaptionMarkup.markdown("a\\*b \\[x\\] c_d", fallbackNumber: 1), "a\\*b \\[x\\] c\\_d")
        XCTAssertEqual(CaptionMarkup.markdown("back\\\\slash", fallbackNumber: 1), "back\\\\slash")
        XCTAssertEqual(CaptionMarkup.markdown("a ` b", fallbackNumber: 1), "a \\` b")
        XCTAssertEqual(CaptionMarkup.markdown("1 < 2 > 0", fallbackNumber: 1), "1 \\< 2 \\> 0")
        // CaptionFormatter writes a UI label's "*" as "\*" inside bold; it must stay literal.
        XCTAssertEqual(CaptionMarkup.markdown("Click **a\\*b**", fallbackNumber: 1), "Click **a\\*b**")
    }

    func testMarkdownCodeSpanSurvivesBackticks() {
        XCTAssertEqual(CaptionMarkup.markdown("Run `ls -la`", fallbackNumber: 1), "Run `ls -la`")
        XCTAssertEqual(CaptionMarkup.markdown("``a`b``", fallbackNumber: 1), "``a`b``")
    }

    func testPlainTextDropsEmphasis() {
        XCTAssertEqual(CaptionMarkup.plainText("Click **Save** in [Safari](https://x)", fallbackNumber: 1), "Click Save in Safari")
    }

    func testEntityNewlinesCannotBreakOutOfHeading() {
        for caption in ["a&#10;# Evil", "a&#13;&#10;- item", "a&#10;~~~", "a&#10;| x | y |"] {
            let md = CaptionMarkup.markdown(caption, fallbackNumber: 1)
            XCTAssertFalse(md.contains(where: \.isNewline), caption)
            XCTAssertFalse(CaptionMarkup.html(caption, fallbackNumber: 1).contains(where: \.isNewline), caption)
            XCTAssertFalse(CaptionMarkup.plainText(caption, fallbackNumber: 1).contains(where: \.isNewline), caption)
        }
        XCTAssertEqual(CaptionMarkup.markdown("a&#10;~~~", fallbackNumber: 1), "a \\~\\~\\~")
        XCTAssertEqual(CaptionMarkup.markdown("a&#10;# Evil", fallbackNumber: 1), "a \\# Evil")
    }

    func testMarkdownEscapesAmpersandAndHash() {
        XCTAssertEqual(CaptionMarkup.markdown("AT&amp;T #", fallbackNumber: 1), "AT\\&T \\#")
        XCTAssertEqual(CaptionMarkup.escapeMarkdown("AT&amp;T #"), "AT\\&amp;T \\#")
    }

    func testBidiControlsAreStripped() {
        let hostile = "a\u{202E}b\u{2066}c\u{2069}d"
        XCTAssertEqual(CaptionMarkup.html(hostile, fallbackNumber: 1), "abcd")
        XCTAssertEqual(CaptionMarkup.markdown(hostile, fallbackNumber: 1), "abcd")
        XCTAssertEqual(CaptionMarkup.escapeHTML(hostile), "abcd")
        XCTAssertEqual(CaptionMarkup.escapeMarkdown(hostile), "abcd")
    }
}
