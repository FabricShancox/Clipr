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

    /// Text that overflows its frame is drawn in full, hanging from the frame's top, instead of
    /// being clipped — clipping dropped typed words from the export.
    func testTallTextIsNotClippedAndHangsFromTheFramesTop() {
        let tall = NSAttributedString(string: "Line1\nLine2\nLine3\nLine4\nLine5\nLine6", attributes: [.font: NSFont.systemFont(ofSize: 40)])
        let frame = CGRect(x: 0, y: 0, width: 100, height: 20)
        for align in [TextVerticalAlign.top, .middle, .bottom] {
            let rect = verticallyAlignedTextRect(tall, in: frame, align: align)
            XCTAssertGreaterThan(rect.height, frame.height)
            XCTAssertEqual(rect.maxY, frame.maxY, accuracy: 0.5)
        }
    }

    private func textAnnotation(_ string: String, frame: CGRect) -> AnnotationObject {
        AnnotationObject(id: UUID(), kind: .text(string, .default), frame: frame,
                         color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1), strokeWidth: 2)
    }

    func testLongTextGrowsItsBoxDownwardKeepingWidthAndTop() {
        let frame = CGRect(x: 10, y: 500, width: 160, height: 28)
        let long = "This sentence is much wider than one hundred and sixty points so it has to wrap"
        let fitted = textAnnotation(long, frame: frame).fittedToText()
        XCTAssertEqual(fitted.frame.width, 160)
        XCTAssertEqual(fitted.frame.maxY, frame.maxY, accuracy: 0.001)
        XCTAssertGreaterThan(fitted.frame.height, frame.height * 2)
        XCTAssertEqual(fitted.frame.height, measuredTextHeight(long, style: .default, width: 160))
    }

    func testShortTextKeepsALargerUserSizedBox() {
        let frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        XCTAssertEqual(textAnnotation("Hi", frame: frame).fittedToText().frame, frame)
    }

    func testOtherKindsAreUnchangedByFitting() {
        let box = AnnotationObject(id: UUID(), kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 5, height: 5),
                                   color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1), strokeWidth: 2)
        XCTAssertEqual(box.fittedToText(), box)
    }

    func testBorderRectIsTheSameOutsetEverywhere() {
        XCTAssertEqual(textBorderRect(for: CGRect(x: 10, y: 10, width: 100, height: 20)), CGRect(x: 6, y: 8, width: 108, height: 24))
    }
}
