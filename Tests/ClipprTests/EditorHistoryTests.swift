import XCTest
@testable import Clipr

final class EditorHistoryTests: XCTestCase {
    private let red = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)

    private func box(_ x: CGFloat = 0) -> AnnotationObject {
        AnnotationObject(id: UUID(), kind: .rectangle, frame: CGRect(x: x, y: 0, width: 10, height: 10), color: red, strokeWidth: 2)
    }

    private func text(_ string: String, id: UUID) -> AnnotationObject {
        AnnotationObject(id: id, kind: .text(string, .default), frame: CGRect(x: 0, y: 0, width: 100, height: 30), color: red, strokeWidth: 2)
    }

    func testANoOpChangeKeepsRedo() {
        var history = EditorHistory()
        let a = box()
        history.record(from: [], to: [a])
        _ = history.popUndo(from: [a])
        XCTAssertEqual(history.redo.count, 1)
        history.record(from: [], to: [])
        XCTAssertEqual(history.redo.count, 1, "a change that changed nothing must not clear redo")
        XCTAssertTrue(history.undo.isEmpty)
    }

    func testARealChangeClearsRedo() {
        var history = EditorHistory()
        let a = box(), b = box(20)
        history.record(from: [], to: [a])
        _ = history.popUndo(from: [a])
        history.record(from: [], to: [b])
        XCTAssertTrue(history.redo.isEmpty)
    }

    func testTypingInOneTextBoxIsOneUndoStep() {
        var history = EditorHistory()
        let id = UUID()
        history.record(from: [], to: [text("", id: id)], group: id)
        var current = [text("", id: id)]
        for prefix in ["h", "he", "hel", "hell", "hello"] {
            let next = [text(prefix, id: id)]
            history.record(from: current, to: next, group: id)
            current = next
        }
        XCTAssertEqual(history.undo.count, 1)
        XCTAssertEqual(history.popUndo(from: current), [], "one undo removes the whole text box")
    }

    func testReEditingAfterClosingStartsANewStep() {
        var history = EditorHistory()
        let id = UUID()
        history.record(from: [], to: [text("a", id: id)], group: id)
        history.closeGroup()
        history.record(from: [text("a", id: id)], to: [text("ab", id: id)], group: id)
        XCTAssertEqual(history.undo.count, 2)
    }

    func testAnAbandonedEmptyTextBoxLeavesNoUndoEntry() {
        var history = EditorHistory()
        let existing = box()
        let id = UUID()
        history.record(from: [], to: [existing])
        history.record(from: [existing], to: [existing, text("", id: id)], group: id)
        // finishTextEditing removes the empty box, still inside the group.
        history.record(from: [existing, text("", id: id)], to: [existing], group: id)
        XCTAssertEqual(history.undo, [[]], "only the box's own step remains")
        XCTAssertNil(history.openGroup)
    }

    func testUndoAndRedoCloseTheGroup() {
        var history = EditorHistory()
        let id = UUID()
        history.record(from: [], to: [text("a", id: id)], group: id)
        _ = history.popUndo(from: [text("a", id: id)])
        XCTAssertNil(history.openGroup)
    }

    func testSelectionIsPrunedToSurvivingAnnotations() {
        let a = box(), b = box(20)
        let selection: Set<UUID> = [a.id, b.id]
        XCTAssertEqual(selection.pruned(to: [a]), [a.id])
    }

    func testNextStampNumberFollowsTheHighestRemaining() {
        let stamp = AnnotationObject(id: UUID(), kind: .stamp(.numbered(3)), frame: .zero, color: red, strokeWidth: 4)
        XCTAssertEqual(nextStampNumber(after: [stamp, box()]), 4)
        XCTAssertEqual(nextStampNumber(after: [box()]), 1)
    }
}
