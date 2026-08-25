import XCTest
import Cocoa
@testable import Clipr

final class AnnotationRendererTests: XCTestCase {
    func testFlattenDrawsRectangleOverBaseImage() {
        let base = NSImage(size: NSSize(width: 20, height: 20))
        base.lockFocus()
        NSColor.white.set()
        NSRect(x: 0, y: 0, width: 20, height: 20).fill()
        base.unlockFocus()

        let redRect = AnnotationObject(
            id: UUID(), kind: .rectangle,
            frame: CGRect(x: 0, y: 0, width: 20, height: 20),
            color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1),
            strokeWidth: 4
        )

        let flattened = AnnotationRenderer.flatten(base: base, annotations: [redRect])
        guard let cgImage = flattened.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            XCTFail("expected a CGImage")
            return
        }
        XCTAssertEqual(cgImage.width, 20)
        XCTAssertEqual(cgImage.height, 20)

        // Sample the center pixel: a 4pt-wide red stroke around the full-size rect should tint it.
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let color = bitmap.colorAt(x: 1, y: 1)
        XCTAssertNotNil(color)
        XCTAssertGreaterThan(color!.redComponent, 0.5, "stroke should be visible near the rectangle edge")
    }

    func testFlattenWithNoAnnotationsReturnsSameSize() {
        let base = NSImage(size: NSSize(width: 10, height: 10))
        base.lockFocus()
        NSColor.blue.set()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        base.unlockFocus()

        let flattened = AnnotationRenderer.flatten(base: base, annotations: [])
        XCTAssertEqual(flattened.size, base.size)
    }
}
