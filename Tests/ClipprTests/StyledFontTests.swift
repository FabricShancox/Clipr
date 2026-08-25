import XCTest
import Cocoa
@testable import Clipr

final class StyledFontTests: XCTestCase {
    func testPlainStyleReturnsUnmodifiedSystemFont() {
        let style = TextStyle(fontSize: 20, bold: false, italic: false, border: true, horizontalAlign: .left, verticalAlign: .top)
        let font = styledFont(style)
        XCTAssertEqual(font.pointSize, 20)
        let traits = NSFontManager.shared.traits(of: font)
        XCTAssertFalse(traits.contains(.boldFontMask))
        XCTAssertFalse(traits.contains(.italicFontMask))
    }

    func testBoldStyleAppliesBoldTrait() {
        let style = TextStyle(fontSize: 20, bold: true, italic: false, border: true, horizontalAlign: .left, verticalAlign: .top)
        let traits = NSFontManager.shared.traits(of: styledFont(style))
        XCTAssertTrue(traits.contains(.boldFontMask))
    }

    func testItalicStyleAppliesItalicTrait() {
        let style = TextStyle(fontSize: 20, bold: false, italic: true, border: true, horizontalAlign: .left, verticalAlign: .top)
        let traits = NSFontManager.shared.traits(of: styledFont(style))
        XCTAssertTrue(traits.contains(.italicFontMask))
    }

    func testFontSizeHasAFloorEvenForATinyRequestedSize() {
        let style = TextStyle(fontSize: 0, bold: false, italic: false, border: true, horizontalAlign: .left, verticalAlign: .top)
        XCTAssertGreaterThanOrEqual(styledFont(style).pointSize, 6)
    }
}
