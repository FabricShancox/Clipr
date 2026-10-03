import XCTest
@testable import Clipr

final class ResizeHandleTests: XCTestCase {
    private let red = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
    private let frame = CGRect(x: 10, y: 10, width: 100, height: 50)

    func testCornerMovesBothAxesAndKeepsOppositeCornerFixed() {
        let resized = ResizeHandle.bottomRight.resizedFrame(frame, draggedTo: CGPoint(x: 150, y: 90))
        XCTAssertEqual(resized, CGRect(x: 10, y: 10, width: 140, height: 80))
    }

    func testEdgeMovesOnlyItsOwnAxis() {
        let resized = ResizeHandle.top.resizedFrame(frame, draggedTo: CGPoint(x: 999, y: 0))
        XCTAssertEqual(resized, CGRect(x: 10, y: 0, width: 100, height: 60))
    }

    func testDraggingPastOppositeSideFlipsInsteadOfGoingNegative() {
        let resized = ResizeHandle.left.resizedFrame(frame, draggedTo: CGPoint(x: 130, y: 0))
        XCTAssertEqual(resized, CGRect(x: 110, y: 10, width: 20, height: 50))
    }

    func testResizingFreehandScalesItsPoints() {
        let stroke = AnnotationObject(
            id: UUID(), kind: .freehand([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]),
            frame: CGRect(x: 0, y: 0, width: 10, height: 10), color: red, strokeWidth: 2
        )
        let resized = stroke.resized(to: CGRect(x: 100, y: 100, width: 20, height: 40))
        XCTAssertEqual(resized.kind, .freehand([CGPoint(x: 100, y: 100), CGPoint(x: 120, y: 140)]))
    }

    func testResizingStraightStrokeDoesNotDivideByZero() {
        let stroke = AnnotationObject(
            id: UUID(), kind: .freehand([CGPoint(x: 0, y: 5), CGPoint(x: 10, y: 5)]),
            frame: CGRect(x: 0, y: 5, width: 10, height: 0), color: red, strokeWidth: 2
        )
        let resized = stroke.resized(to: CGRect(x: 0, y: 5, width: 30, height: 0))
        XCTAssertEqual(resized.kind, .freehand([CGPoint(x: 0, y: 5), CGPoint(x: 30, y: 5)]))
    }

    func testMovingArrowEndpointKeepsTheOtherEndAndUpdatesFrame() {
        let arrow = AnnotationObject(
            id: UUID(), kind: .arrow(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)),
            frame: CGRect(x: 0, y: 0, width: 10, height: 0), color: red, strokeWidth: 2
        )
        let moved = arrow.movingArrowEndpoint(start: false, to: CGPoint(x: 40, y: 30))
        XCTAssertEqual(moved.kind, .arrow(CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 30)))
        XCTAssertEqual(moved.frame, CGRect(x: 0, y: 0, width: 40, height: 30))
    }

    func testHorizontalArrowHasAGenerousHitArea() {
        let arrow = AnnotationObject(
            id: UUID(), kind: .arrow(CGPoint(x: 0, y: 100), CGPoint(x: 200, y: 100)),
            frame: CGRect(x: 0, y: 100, width: 200, height: 0), color: red, strokeWidth: 2
        )
        // Well off the line itself, but within the head's reach.
        XCTAssertTrue(arrow.contains(CGPoint(x: 100, y: 112)))
        XCTAssertFalse(arrow.contains(CGPoint(x: 100, y: 140)))
        // A zoom-adjusted tolerance widens it further.
        XCTAssertTrue(arrow.contains(CGPoint(x: 100, y: 125), tolerance: 30))
    }

    func testStampSideFollowsStrokePresets() {
        XCTAssertEqual(StampKind.side(forStrokeWidth: 4), 32)
        XCTAssertLessThan(StampKind.side(forStrokeWidth: 2), StampKind.side(forStrokeWidth: 8))
    }

    func testBorderIsAddedAroundTheImage() {
        let image = testImage(width: 100, height: 60) {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 100, height: 60).fill()
        }
        let bordered = AnnotationRenderer.addingBorder(to: image, width: 3)
        XCTAssertEqual(bordered.size, NSSize(width: 106, height: 66))
    }
}
