import XCTest
@testable import Clipr

/// Arrows and freehand strokes are thin lines; a click only counts as hitting one when it lands
/// near the drawn line, not anywhere inside the (possibly huge) bounding box of a diagonal.
final class PathHitTestTests: XCTestCase {
    private let red = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)

    private var diagonalArrow: AnnotationObject {
        AnnotationObject(
            id: UUID(), kind: .arrow(CGPoint(x: 0, y: 1000), CGPoint(x: 1000, y: 0)),
            frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), color: red, strokeWidth: 4
        )
    }

    func testDiagonalArrowIsHitOnItsShaft() {
        XCTAssertTrue(diagonalArrow.contains(CGPoint(x: 500, y: 505), tolerance: 12))
        XCTAssertTrue(diagonalArrow.outlineContains(CGPoint(x: 500, y: 505), tolerance: 12))
    }

    func testDiagonalArrowIsNotHitInTheEmptyCornerOfItsBoundingBox() {
        XCTAssertFalse(diagonalArrow.contains(CGPoint(x: 100, y: 100), tolerance: 12))
        XCTAssertFalse(diagonalArrow.outlineContains(CGPoint(x: 900, y: 900), tolerance: 12))
    }

    func testArrowHeadStillCountsNearTheTip() {
        // Just past the tip, inside the head's reach.
        XCTAssertTrue(diagonalArrow.contains(CGPoint(x: 1005, y: -5), tolerance: 1))
    }

    func testFreehandIsHitOnlyNearItsPolyline() {
        let stroke = AnnotationObject(
            id: UUID(), kind: .freehand([CGPoint(x: 0, y: 0), CGPoint(x: 500, y: 0), CGPoint(x: 500, y: 500)]),
            frame: CGRect(x: 0, y: 0, width: 500, height: 500), color: red, strokeWidth: 4
        )
        XCTAssertTrue(stroke.contains(CGPoint(x: 250, y: 6), tolerance: 10))
        XCTAssertTrue(stroke.contains(CGPoint(x: 495, y: 250), tolerance: 10))
        XCTAssertFalse(stroke.contains(CGPoint(x: 100, y: 400), tolerance: 10))
    }

    func testSinglePointFreehandUsesDistanceToThatPoint() {
        let dot = AnnotationObject(
            id: UUID(), kind: .freehand([CGPoint(x: 50, y: 50)]),
            frame: CGRect(x: 50, y: 50, width: 0, height: 0), color: red, strokeWidth: 4
        )
        XCTAssertTrue(dot.contains(CGPoint(x: 55, y: 55), tolerance: 10))
        XCTAssertFalse(dot.contains(CGPoint(x: 80, y: 80), tolerance: 10))
    }

    func testRectangleStillUsesItsWholeFrame() {
        let box = AnnotationObject(id: UUID(), kind: .rectangle, frame: CGRect(x: 0, y: 0, width: 100, height: 100), color: red, strokeWidth: 2)
        XCTAssertTrue(box.contains(CGPoint(x: 50, y: 50)))
    }
}
