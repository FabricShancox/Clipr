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

    func testTrailKeepsOnlyFinalInImageRunAndFlips() throws {
        let origin = CGPoint(x: 1000, y: 500)
        // (900,510) is off-image: everything before it is dropped rather than joined by a chord.
        let points = [CGPoint(x: 1010, y: 510), CGPoint(x: 900, y: 510), CGPoint(x: 1020, y: 520), CGPoint(x: 1050, y: 560)]
        let a = try XCTUnwrap(StepAnnotationFactory.trail(globalPoints: points, captureOrigin: origin, imageSize: size))
        guard case .freehand(let pts) = a.kind else { return XCTFail("not freehand") }
        XCTAssertEqual(pts.first, CGPoint(x: 20, y: 280))
        XCTAssertEqual(pts.last, CGPoint(x: 50, y: 240))   // ends on the click, renderer space
        XCTAssertEqual(a.frame, CGRect(x: 20, y: 240, width: 30, height: 40))
        XCTAssertEqual(a.strokeWidth, 2.5)
        XCTAssertEqual(a.color.alpha, 0.5, accuracy: 0.001)
    }

    func testTrailIsTrimmedToLastStretchBeforeClick() throws {
        // 600pt straight path along y = 100 ending at the click (390, 100).
        let points = stride(from: 0, through: 390, by: 30).map { CGPoint(x: CGFloat($0), y: 100) }
        let a = try XCTUnwrap(StepAnnotationFactory.trail(globalPoints: points, captureOrigin: .zero, imageSize: size))
        guard case .freehand(let pts) = a.kind else { return XCTFail("not freehand") }
        XCTAssertEqual(pts.last, CGPoint(x: 390, y: 200))
        XCTAssertEqual(StepAnnotationFactory.pathLength(pts), StepAnnotationFactory.trailMaxLength, accuracy: 0.5)
    }

    func testTrailTooShortIsDropped() {
        XCTAssertNil(StepAnnotationFactory.trail(globalPoints: [CGPoint(x: 100, y: 100), CGPoint(x: 110, y: 100)],
                                                 captureOrigin: .zero, imageSize: size))
    }

    func testSmoothingKeepsEndpointsAndRoundsCorners() {
        let corner = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)]
        let s = StepAnnotationFactory.smoothed(corner)
        XCTAssertEqual(s.first, corner.first)
        XCTAssertEqual(s.last, corner.last)
        XCTAssertFalse(s.contains(CGPoint(x: 100, y: 0)))   // the sharp corner is cut
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
