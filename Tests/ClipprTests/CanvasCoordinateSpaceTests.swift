import XCTest
@testable import Clipr

final class CanvasCoordinateSpaceTests: XCTestCase {
    let canvasHeight: CGFloat = 200

    func testRendererFrameFlipsYRelativeToCanvasHeight() {
        // A rect at the SwiftUI-space top (y=0) with height 50 should end up at the renderer-
        // space TOP too, i.e. its bottom-left-origin y should be canvasHeight - height.
        let result = rendererFrame(fromSwiftUIFrame: CGRect(x: 10, y: 0, width: 30, height: 50), canvasHeight: canvasHeight)
        XCTAssertEqual(result, CGRect(x: 10, y: 150, width: 30, height: 50))
    }

    func testSwiftUIFrameIsTheExactInverseOfRendererFrame() {
        let original = CGRect(x: 15, y: 40, width: 60, height: 25)
        let renderer = rendererFrame(fromSwiftUIFrame: original, canvasHeight: canvasHeight)
        let roundTripped = swiftUIFrame(fromRendererFrame: renderer, canvasHeight: canvasHeight)
        XCTAssertEqual(roundTripped, original)
    }

    func testRendererPointFlipsY() {
        XCTAssertEqual(rendererPoint(fromSwiftUIPoint: CGPoint(x: 5, y: 0), canvasHeight: canvasHeight), CGPoint(x: 5, y: 200))
        XCTAssertEqual(rendererPoint(fromSwiftUIPoint: CGPoint(x: 5, y: 200), canvasHeight: canvasHeight), CGPoint(x: 5, y: 0))
    }

    func testPointConversionIsSelfInverse() {
        let original = CGPoint(x: 33, y: 77)
        let renderer = rendererPoint(fromSwiftUIPoint: original, canvasHeight: canvasHeight)
        let back = swiftUIPoint(fromRendererPoint: renderer, canvasHeight: canvasHeight)
        XCTAssertEqual(back, original)
    }
}
