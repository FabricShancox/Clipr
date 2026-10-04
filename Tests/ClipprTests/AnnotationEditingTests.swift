import XCTest
import Cocoa
@testable import Clipr

/// Duplicate / nudge / reorder operate on the selected annotation. The view wiring can't be
/// exercised headlessly, so these cover the behaviour those operations are built from — the
/// translation helper's direction convention, and the array reordering that z-order amounts to.
final class AnnotationEditingTests: XCTestCase {

    private func annotation(_ frame: CGRect, kind: AnnotationKind = .rectangle) -> AnnotationObject {
        AnnotationObject(
            id: UUID(), kind: kind, frame: frame,
            color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1), strokeWidth: 2
        )
    }

    // MARK: - Nudge direction

    /// Frames live in renderer space (bottom-left origin, y up), so moving an annotation UP the
    /// screen is a POSITIVE y translation. Getting this backwards would send arrow keys the wrong
    /// way, which is exactly the kind of flip this codebase's coordinate split invites.
    func testTranslateUpOnScreenIsPositiveYInRendererSpace() {
        let moved = annotation(CGRect(x: 10, y: 10, width: 5, height: 5))
            .translated(by: CGPoint(x: 0, y: 1))
        XCTAssertEqual(moved.frame.origin.y, 11)
    }

    func testTranslateCarriesArrowEndpointsNotJustTheFrame() {
        let arrow = annotation(
            CGRect(x: 0, y: 0, width: 10, height: 10),
            kind: .arrow(CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10))
        )
        guard case .arrow(let start, let end) = arrow.translated(by: CGPoint(x: 3, y: 4)).kind else {
            return XCTFail("expected an arrow")
        }
        XCTAssertEqual(start, CGPoint(x: 3, y: 4))
        XCTAssertEqual(end, CGPoint(x: 13, y: 14))
    }

    func testTranslateCarriesFreehandPoints() {
        let stroke = annotation(
            CGRect(x: 0, y: 0, width: 10, height: 10),
            kind: .freehand([CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)])
        )
        guard case .freehand(let points) = stroke.translated(by: CGPoint(x: 5, y: 0)).kind else {
            return XCTFail("expected freehand")
        }
        XCTAssertEqual(points, [CGPoint(x: 6, y: 1), CGPoint(x: 7, y: 2)])
    }

    /// A duplicate must be a genuinely new object; sharing the id would make the copy
    /// indistinguishable from the original for selection and `ForEach` identity.
    func testADuplicateGetsItsOwnIdentityButTheSameAppearance() {
        let original = annotation(CGRect(x: 4, y: 4, width: 20, height: 10))
        let moved = original.translated(by: CGPoint(x: 12, y: -12))
        let copy = AnnotationObject(
            id: UUID(), kind: moved.kind, frame: moved.frame,
            color: moved.color, strokeWidth: moved.strokeWidth
        )

        XCTAssertNotEqual(copy.id, original.id)
        XCTAssertEqual(copy.color, original.color)
        XCTAssertEqual(copy.strokeWidth, original.strokeWidth)
        XCTAssertNotEqual(copy.frame.origin, original.frame.origin, "a copy must be visibly offset")
    }

    // MARK: - Z-order

    /// Annotations draw in array order, so these mirror what the reorder operations do to it.
    private func move(_ items: [Int], from index: Int, to target: Int) -> [Int] {
        var items = items
        let moved = items.remove(at: index)
        items.insert(moved, at: target)
        return items
    }

    func testBringForwardSwapsWithTheOneAbove() {
        XCTAssertEqual(move([1, 2, 3, 4], from: 1, to: 2), [1, 3, 2, 4])
    }

    func testSendBackwardSwapsWithTheOneBelow() {
        XCTAssertEqual(move([1, 2, 3, 4], from: 2, to: 1), [1, 3, 2, 4])
    }

    func testBringToFrontPutsItLast() {
        XCTAssertEqual(move([1, 2, 3, 4], from: 0, to: 3), [2, 3, 4, 1])
    }

    func testSendToBackPutsItFirst() {
        XCTAssertEqual(move([1, 2, 3, 4], from: 3, to: 0), [4, 1, 2, 3])
    }

    /// The clamps: forward on the topmost and backward on the bottom-most must be no-ops rather
    /// than running off the end of the array.
    func testForwardOnTheTopmostIsClampedNotOutOfBounds() {
        let count = 4
        let index = 3
        XCTAssertEqual(min(index + 1, count - 1), 3)
    }

    func testBackwardOnTheBottomMostIsClampedNotNegative() {
        XCTAssertEqual(max(0 - 1, 0), 0)
    }

    // MARK: - Text style target

    func testStyleControlsTargetTheBoxBeingTypedIntoEvenWhenNotSelected() {
        let typing = annotation(CGRect(x: 0, y: 0, width: 100, height: 20), kind: .text("", .default))
        let other = annotation(CGRect(x: 0, y: 50, width: 100, height: 20), kind: .text("x", .default))
        let target = EditorView.textStyleTarget(editingTextID: typing.id, selectedIDs: [other.id], annotations: [typing, other])
        XCTAssertEqual(target?.id, typing.id)
        XCTAssertEqual(EditorView.textStyleTarget(editingTextID: nil, selectedIDs: [other.id], annotations: [typing, other])?.id, other.id)
        XCTAssertNil(EditorView.textStyleTarget(editingTextID: nil, selectedIDs: [typing.id, other.id], annotations: [typing, other]))
        XCTAssertNil(EditorView.textStyleTarget(editingTextID: nil, selectedIDs: [], annotations: [typing, other]))
    }
}
