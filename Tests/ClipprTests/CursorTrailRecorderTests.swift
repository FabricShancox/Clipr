import XCTest
@testable import Clipr

final class CursorTrailRecorderTests: XCTestCase {
    func testDropsPointsCloserThanMinDistance() {
        var r = CursorTrailRecorder()
        r.add(CGPoint(x: 0, y: 0))
        r.add(CGPoint(x: 3, y: 4))   // distance 5 — dropped
        r.add(CGPoint(x: 6, y: 8))   // distance 10 from (0,0) — kept
        XCTAssertEqual(r.points, [CGPoint(x: 0, y: 0), CGPoint(x: 6, y: 8)])
    }

    func testCapDropsOldest() {
        var r = CursorTrailRecorder()
        for i in 0..<(CursorTrailRecorder.maxPoints + 5) {
            r.add(CGPoint(x: CGFloat(i) * 10, y: 0))
        }
        XCTAssertEqual(r.points.count, CursorTrailRecorder.maxPoints)
        XCTAssertEqual(r.points.first, CGPoint(x: 50, y: 0))
    }

    func testDrainReturnsAndResets() {
        var r = CursorTrailRecorder()
        r.add(CGPoint(x: 0, y: 0)); r.add(CGPoint(x: 20, y: 0))
        XCTAssertEqual(r.drain().count, 2)
        XCTAssertTrue(r.points.isEmpty)
        r.add(CGPoint(x: 1, y: 1))
        XCTAssertEqual(r.points, [CGPoint(x: 1, y: 1)])  // no distance filter against drained points
    }
}
