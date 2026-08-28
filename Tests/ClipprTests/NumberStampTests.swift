import XCTest
import Cocoa
@testable import Clipr

/// Numbered stamps are drawn as a solid disc with the digit painted on top in a contrasting
/// colour, rather than the `"N.circle.fill"` SF Symbol whose digit is a transparent cutout.
/// These cover both halves of that: which foreground each stamp colour picks, and that the
/// flattened render really is opaque where the old cutout used to let the capture show through.
final class NumberStampTests: XCTestCase {

    // MARK: - Contrast selection

    /// The editor's own swatches are the colours that actually matter here.
    private func swatch(_ hex: (CGFloat, CGFloat, CGFloat)) -> RGBAColor {
        RGBAColor(red: hex.0, green: hex.1, blue: hex.2, alpha: 1)
    }

    func testLightStampColoursGetABlackDigit() {
        let light: [(String, (CGFloat, CGFloat, CGFloat))] = [
            ("white", (1, 1, 1)),
            ("grey", (0x91 / 255, 0x9E / 255, 0xAB / 255)),
            ("orange", (1, 0xB7 / 255, 0x4D / 255))
        ]
        for (name, components) in light {
            let fg = swatch(components).contrastingForeground
            XCTAssertEqual(fg.red, 0, "\(name) should take a black digit")
            XCTAssertEqual(fg.green, 0, "\(name) should take a black digit")
            XCTAssertEqual(fg.blue, 0, "\(name) should take a black digit")
        }
    }

    func testDarkAndSaturatedStampColoursGetAWhiteDigit() {
        let dark: [(String, (CGFloat, CGFloat, CGFloat))] = [
            ("red", (0xF4 / 255, 0x43 / 255, 0x36 / 255)),
            ("blue", (0x33 / 255, 0x99 / 255, 1)),
            ("purple", (0x8E / 255, 0x33 / 255, 1)),
            ("black", (0, 0, 0))
        ]
        for (name, components) in dark {
            let fg = swatch(components).contrastingForeground
            XCTAssertEqual(fg.red, 1, "\(name) should take a white digit")
            XCTAssertEqual(fg.green, 1, "\(name) should take a white digit")
            XCTAssertEqual(fg.blue, 1, "\(name) should take a white digit")
        }
    }

    /// Red is the case the brief called out explicitly, and it is the one a plain 0.5 midpoint
    /// would get wrong — guard the threshold that makes it come out white.
    func testRedTakesAWhiteDigitDespiteBeingNearTheMidpoint() {
        let red = RGBAColor(red: 0xF4 / 255, green: 0x43 / 255, blue: 0x36 / 255, alpha: 1)
        XCTAssertGreaterThan(red.perceivedLuminance, 0.4)
        XCTAssertLessThan(red.perceivedLuminance, 0.6)
        XCTAssertEqual(red.contrastingForeground.red, 1, "red should read with a white digit")
    }

    func testContrastingForegroundKeepsTheStampsAlpha() {
        let translucent = RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.4)
        XCTAssertEqual(translucent.contrastingForeground.alpha, 0.4)
    }

    // MARK: - StampKind

    func testNumberStampsExposeTheirDigitAndOthersDoNot() {
        XCTAssertEqual(StampKind.number1.number, 1)
        XCTAssertEqual(StampKind.number9.number, 9)
        XCTAssertNil(StampKind.check.number)
        XCTAssertNil(StampKind.cross.number)
        XCTAssertNil(StampKind.star.number)
    }

    // MARK: - Flattened render

    private func flattenedStamp(color: RGBAColor, over background: NSColor) -> NSBitmapImageRep? {
        let base = NSImage(size: NSSize(width: 60, height: 60))
        base.lockFocus()
        background.set()
        NSRect(x: 0, y: 0, width: 60, height: 60).fill()
        base.unlockFocus()

        let stamp = AnnotationObject(
            id: UUID(), kind: .stamp(.number1),
            frame: CGRect(x: 10, y: 10, width: 40, height: 40),
            color: color,
            strokeWidth: 1
        )
        let flattened = AnnotationRenderer.flatten(base: base, annotations: [stamp])
        guard let cg = flattened.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg)
    }

    /// The regression this whole change is about: with the old cutout symbol the green backdrop
    /// showed straight through the disc, so a stamp over a busy screenshot was hard to read.
    func testDiscIsOpaqueSoTheCaptureDoesNotShowThrough() throws {
        let red = RGBAColor(red: 1, green: 0, blue: 0, alpha: 1)
        let bitmap = try XCTUnwrap(flattenedStamp(color: red, over: .green))

        // Just inside the disc's left edge — clear of the digit, which sits in the middle.
        let edge = try XCTUnwrap(bitmap.colorAt(x: 16, y: 30))
        XCTAssertGreaterThan(edge.redComponent, 0.8, "disc should be filled with the stamp colour")
        XCTAssertLessThan(edge.greenComponent, 0.3, "backdrop must not show through the disc")
    }

    func testDigitIsPaintedInTheContrastingColour() throws {
        // A white stamp takes a black digit, so the darkest pixel in the middle of the disc is
        // the digit itself — over a white backdrop that can only have come from the glyph.
        let white = RGBAColor(red: 1, green: 1, blue: 1, alpha: 1)
        let bitmap = try XCTUnwrap(flattenedStamp(color: white, over: .white))

        var darkest: CGFloat = 1
        for x in 20...40 {
            for y in 20...40 {
                if let c = bitmap.colorAt(x: x, y: y) { darkest = min(darkest, c.brightnessComponent) }
            }
        }
        XCTAssertLessThan(darkest, 0.35, "a dark digit should be drawn on the light disc")
    }

    func testDigitContrastsOnADarkStampToo() throws {
        // Mirror image of the above: a black stamp takes a white digit, so over a black backdrop
        // the brightest pixel inside the disc must be the glyph.
        let black = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
        let bitmap = try XCTUnwrap(flattenedStamp(color: black, over: .black))

        var brightest: CGFloat = 0
        for x in 20...40 {
            for y in 20...40 {
                if let c = bitmap.colorAt(x: x, y: y) { brightest = max(brightest, c.brightnessComponent) }
            }
        }
        XCTAssertGreaterThan(brightest, 0.65, "a light digit should be drawn on the dark disc")
    }
}
