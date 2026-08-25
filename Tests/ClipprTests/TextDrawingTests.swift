import XCTest
import Cocoa
@testable import Clipr

final class TextDrawingTests: XCTestCase {
    func testParagraphStyleMapsEachAlignCase() {
        XCTAssertEqual(textParagraphStyle(for: .left).alignment, .left)
        XCTAssertEqual(textParagraphStyle(for: .center).alignment, .center)
        XCTAssertEqual(textParagraphStyle(for: .right).alignment, .right)
    }

    private func shortAttributedString() -> NSAttributedString {
        NSAttributedString(string: "Hi", attributes: [.font: NSFont.systemFont(ofSize: 14)])
    }

    func testVerticalAlignTopSitsAtTheFramesTopEdge() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 200)
        let rect = verticallyAlignedTextRect(shortAttributedString(), in: frame, align: .top)
        // In this y-up frame, "top" is the far edge from the origin — the returned rect's
        // top (maxY) should coincide with the frame's own top (maxY).
        XCTAssertEqual(rect.maxY, frame.maxY, accuracy: 0.5)
    }

    func testVerticalAlignBottomSitsAtTheFramesBottomEdge() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 200)
        let rect = verticallyAlignedTextRect(shortAttributedString(), in: frame, align: .bottom)
        XCTAssertEqual(rect.minY, frame.minY, accuracy: 0.5)
    }

    func testVerticalAlignMiddleIsBetweenTopAndBottom() {
        let frame = CGRect(x: 0, y: 0, width: 100, height: 200)
        let top = verticallyAlignedTextRect(shortAttributedString(), in: frame, align: .top)
        let middle = verticallyAlignedTextRect(shortAttributedString(), in: frame, align: .middle)
        let bottom = verticallyAlignedTextRect(shortAttributedString(), in: frame, align: .bottom)
        XCTAssertLessThan(bottom.minY, middle.minY)
        XCTAssertLessThan(middle.minY, top.minY)
    }

    func testMeasuredHeightNeverExceedsTheFrameEvenForVeryTallText() {
        let tall = NSAttributedString(string: "Line1\nLine2\nLine3\nLine4\nLine5\nLine6", attributes: [.font: NSFont.systemFont(ofSize: 40)])
        let frame = CGRect(x: 0, y: 0, width: 100, height: 20)
        let rect = verticallyAlignedTextRect(tall, in: frame, align: .top)
        XCTAssertLessThanOrEqual(rect.height, frame.height)
    }
}
