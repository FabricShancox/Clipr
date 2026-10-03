import XCTest
@testable import Clipr

final class AnnotationClipboardTests: XCTestCase {
    private let red = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)

    private func box(_ frame: CGRect) -> AnnotationObject {
        AnnotationObject(id: UUID(), kind: .rectangle, frame: frame, color: red, strokeWidth: 4)
    }

    func testPasteGivesFreshIDsAndKeepsRedactionStyle() {
        var redaction = box(CGRect(x: 10, y: 10, width: 50, height: 50))
        redaction.kind = .blur
        redaction.redactionStyle = .solid
        let clipboard = AnnotationClipboard(canvasHeight: 400, annotations: [redaction])
        let pasted = clipboard.annotationsForPaste(into: CGSize(width: 400, height: 400), existing: [])
        XCTAssertEqual(pasted.count, 1)
        XCTAssertNotEqual(pasted[0].id, redaction.id)
        XCTAssertEqual(pasted[0].redactionStyle, .solid)
        XCTAssertEqual(pasted[0].frame, redaction.frame)
    }

    func testPasteOntoItsOwnOriginalIsOffset() {
        let original = box(CGRect(x: 10, y: 100, width: 50, height: 50))
        let clipboard = AnnotationClipboard(canvasHeight: 400, annotations: [original])
        let pasted = clipboard.annotationsForPaste(into: CGSize(width: 400, height: 400), existing: [original])
        XCTAssertEqual(pasted[0].frame.origin, CGPoint(x: 22, y: 88))
    }

    func testPasteIntoTallerCaptureKeepsDistanceFromTop() {
        // 50pt below the top of a 400pt canvas (renderer space is y-up).
        let original = box(CGRect(x: 10, y: 300, width: 50, height: 50))
        let clipboard = AnnotationClipboard(canvasHeight: 400, annotations: [original])
        let pasted = clipboard.annotationsForPaste(into: CGSize(width: 400, height: 1000), existing: [])
        XCTAssertEqual(pasted[0].frame.maxY, 950)
    }

    func testPasteThatWouldLandOffCanvasIsPulledIntoView() {
        let original = box(CGRect(x: 900, y: 10, width: 50, height: 50))
        let clipboard = AnnotationClipboard(canvasHeight: 400, annotations: [original])
        let pasted = clipboard.annotationsForPaste(into: CGSize(width: 300, height: 400), existing: [])
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 300, height: 400).intersects(pasted[0].frame))
    }

    func testRoundTripsThroughAPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("clipr-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let clipboard = AnnotationClipboard(canvasHeight: 400, annotations: [box(CGRect(x: 1, y: 2, width: 3, height: 4))])
        clipboard.write(to: pasteboard)
        XCTAssertEqual(AnnotationClipboard.read(from: pasteboard), clipboard)
    }

    func testBoxOutlineIsGrabbableButItsMiddleIsNot() {
        let annotation = box(CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertTrue(annotation.outlineContains(CGPoint(x: 2, y: 100), tolerance: 10))
        XCTAssertFalse(annotation.outlineContains(CGPoint(x: 100, y: 100), tolerance: 10))
        // `contains` still treats the whole box as a target, for the Select tool.
        XCTAssertTrue(annotation.contains(CGPoint(x: 100, y: 100), tolerance: 10))
    }

    func testEllipseOutlineIgnoresMiddleAndFrameCorners() {
        var ellipse = box(CGRect(x: 0, y: 0, width: 200, height: 200))
        ellipse.kind = .ellipse
        XCTAssertTrue(ellipse.outlineContains(CGPoint(x: 100, y: 2), tolerance: 10))
        XCTAssertFalse(ellipse.outlineContains(CGPoint(x: 100, y: 100), tolerance: 10))
        XCTAssertFalse(ellipse.outlineContains(CGPoint(x: 2, y: 2), tolerance: 10))
    }

    func testCopyStylePadsTheImage() {
        let image = testImage(width: 120, height: 80) {
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 120, height: 80).fill()
        }
        XCTAssertEqual(AnnotationRenderer.applying(CopyStyle(), to: image).size, image.size)
        let shadowed = AnnotationRenderer.applying(CopyStyle(border: false, shadow: true), to: image)
        XCTAssertGreaterThan(shadowed.size.width, image.size.width)
        XCTAssertGreaterThan(shadowed.size.height, image.size.height)
    }

    func testCommandKeysMapOnlyWithPlainCommand() {
        func key(_ chars: String, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: 0
            )!
        }
        XCTAssertEqual(EditorCommands.action(for: key("c", .command)), .copy)
        XCTAssertEqual(EditorCommands.action(for: key("v", .command)), .paste)
        XCTAssertEqual(EditorCommands.action(for: key("a", .command)), .selectAll)
        XCTAssertNil(EditorCommands.action(for: key("c", [.command, .shift])))
        XCTAssertNil(EditorCommands.action(for: key("c", [])))
    }
}
