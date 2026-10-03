import XCTest
@testable import Clipr

final class StepAnnotationFactoryTests: XCTestCase {
    let size = CGSize(width: 400, height: 300)

    func testRingIsCenteredInRendererSpace() {
        let a = StepAnnotationFactory.marker(at: CGPoint(x: 100, y: 50), style: .ring, imageSize: size)
        XCTAssertEqual(a.kind, .ellipse)
        // top-left y 50 → renderer y 250; 36 pt ring centred there.
        XCTAssertEqual(a.frame, CGRect(x: 82, y: 232, width: 36, height: 36))
        XCTAssertEqual(a.strokeWidth, 3)
        XCTAssertEqual(a.color, StepAnnotationFactory.markerColor)
    }

    func testDotIsSmallAndFilledByStroke() {
        let a = StepAnnotationFactory.marker(at: CGPoint(x: 100, y: 50), style: .dot, imageSize: size)
        XCTAssertEqual(a.frame, CGRect(x: 96.5, y: 246.5, width: 7, height: 7))
        XCTAssertEqual(a.strokeWidth, 7)

        // Integration: verify the dot renders as a solid filled circle
        let base = testImage(width: 400, height: 300) { NSColor.white.set(); NSRect(x: 0, y: 0, width: 400, height: 300).fill() }
        let dot = StepAnnotationFactory.marker(at: CGPoint(x: 100, y: 50), style: .dot, imageSize: size)
        let flat = AnnotationRenderer.flatten(base: base, annotations: [dot])
        let rep = NSBitmapImageRep(cgImage: flat.bitmap!)

        // Center of the dot should be red
        let centerColor = rep.colorAt(x: 100, y: 50)!
        XCTAssertGreaterThan(centerColor.redComponent, 0.8)
        XCTAssertLessThan(centerColor.greenComponent, 0.5)

        // Just outside the 7pt radius (at distance ~7.5 from center) should be white
        let outsideColor = rep.colorAt(x: 109, y: 50)!
        XCTAssertGreaterThan(outsideColor.greenComponent, 0.9)
    }

    func testTrailMapsClipsAndFlips() throws {
        let origin = CGPoint(x: 1000, y: 500)
        let points = [CGPoint(x: 1010, y: 510), CGPoint(x: 900, y: 510), CGPoint(x: 1050, y: 560)]
        let a = try XCTUnwrap(StepAnnotationFactory.trail(globalPoints: points, captureOrigin: origin, imageSize: size))
        guard case .freehand(let pts) = a.kind else { return XCTFail("not freehand") }
        XCTAssertEqual(pts, [CGPoint(x: 10, y: 290), CGPoint(x: 50, y: 240)])  // off-image point dropped
        XCTAssertEqual(a.frame, CGRect(x: 10, y: 240, width: 40, height: 50))
        XCTAssertEqual(a.strokeWidth, 2)
        XCTAssertEqual(a.color.alpha, 0.6, accuracy: 0.001)
    }

    func testTrailNeedsTwoPointsInside() {
        XCTAssertNil(StepAnnotationFactory.trail(globalPoints: [CGPoint(x: 5, y: 5)], captureOrigin: .zero, imageSize: size))
        XCTAssertNil(StepAnnotationFactory.trail(globalPoints: [CGPoint(x: 5, y: 5), CGPoint(x: -5, y: 5)],
                                                 captureOrigin: .zero, imageSize: size))
    }

    func testMarkerRendersWhereClicked() {
        // Integration: flatten a marker onto a white image and check the ring's left edge pixel.
        let base = testImage(width: 400, height: 300) { NSColor.white.set(); NSRect(x: 0, y: 0, width: 400, height: 300).fill() }
        let ring = StepAnnotationFactory.marker(at: CGPoint(x: 100, y: 50), style: .ring, imageSize: size)
        let flat = AnnotationRenderer.flatten(base: base, annotations: [ring])
        let rep = NSBitmapImageRep(cgImage: flat.bitmap!)
        // Bitmap rows are top-down: the ring's left edge is at x≈82, top-left y 50.
        // Check the solid red stroke at the left edge, not the blended anti-alias edge.
        let c = rep.colorAt(x: 82, y: 50)!
        XCTAssertGreaterThan(c.redComponent, 0.8)
        XCTAssertLessThan(c.greenComponent, 0.5)
    }
}
