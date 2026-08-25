import XCTest
@testable import Clipr

final class ArrowGeometryTests: XCTestCase {
    func testHeadLengthScalesWithStrokeWidthButHasAFloor() {
        XCTAssertEqual(arrowHeadLength(for: 1), 14) // floor, not 3.5
        XCTAssertEqual(arrowHeadLength(for: 10), 35)
    }

    func testGeometryTipMatchesRequestedEndpoint() {
        let geo = arrowGeometry(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), strokeWidth: 4)
        XCTAssertEqual(geo.tip, CGPoint(x: 100, y: 0))
    }

    func testShaftStopsShortOfTipByExactlyTheHeadLength() {
        let geo = arrowGeometry(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), strokeWidth: 4)
        let headLength = arrowHeadLength(for: 4)
        XCTAssertEqual(geo.tip.x - geo.shaftEnd.x, headLength, accuracy: 0.001)
        XCTAssertEqual(geo.shaftEnd.y, 0, accuracy: 0.001)
    }

    func testHeadCornersAreSymmetricAboutTheShaftLine() {
        let geo = arrowGeometry(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), strokeWidth: 4)
        // For a horizontal arrow, the two head corners should mirror across the line (y == 0).
        XCTAssertEqual(geo.corner1.y, -geo.corner2.y, accuracy: 0.001)
        XCTAssertEqual(geo.corner1.x, geo.corner2.x, accuracy: 0.001)
    }

    func testGeometryToleratesAZeroLengthArrowWithoutDividingByZero() {
        let geo = arrowGeometry(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 5, y: 5), strokeWidth: 4)
        XCTAssertFalse(geo.shaftEnd.x.isNaN)
        XCTAssertFalse(geo.corner1.x.isNaN)
    }
}
