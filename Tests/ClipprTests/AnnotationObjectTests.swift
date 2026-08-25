import XCTest
@testable import Clipr

final class AnnotationObjectTests: XCTestCase {
    func testContainsPointInsideFrame() {
        let obj = AnnotationObject(id: UUID(), kind: .rectangle, frame: CGRect(x: 10, y: 10, width: 100, height: 50), color: .init(red: 1, green: 0, blue: 0, alpha: 1), strokeWidth: 2)
        XCTAssertTrue(obj.contains(CGPoint(x: 50, y: 30)))
    }

    func testContainsPointOutsideFrame() {
        let obj = AnnotationObject(id: UUID(), kind: .rectangle, frame: CGRect(x: 10, y: 10, width: 100, height: 50), color: .init(red: 1, green: 0, blue: 0, alpha: 1), strokeWidth: 2)
        XCTAssertFalse(obj.contains(CGPoint(x: 500, y: 500)))
    }

    func testStampSymbolNames() {
        XCTAssertEqual(StampKind.check.symbolName, "checkmark.circle.fill")
        XCTAssertEqual(StampKind.number3.symbolName, "3.circle.fill")
    }

    func testCodableRoundTrip() throws {
        let obj = AnnotationObject(id: UUID(), kind: .text("hello"), frame: CGRect(x: 0, y: 0, width: 40, height: 20), color: .init(red: 0, green: 0, blue: 0, alpha: 1), strokeWidth: 1)
        let data = try JSONEncoder().encode(obj)
        let decoded = try JSONDecoder().decode(AnnotationObject.self, from: data)
        XCTAssertEqual(decoded, obj)
    }
}
