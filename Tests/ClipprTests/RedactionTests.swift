import XCTest
import Cocoa
@testable import Clipr

/// The `.blur` tool is a redaction tool, so these assert the property that actually matters: the
/// information under a redaction must be *destroyed* in the export, not merely dimmed.
///
/// It previously painted `gray 0.5, alpha 0.9`, which left a tenth of every original pixel in the
/// file — raising the contrast on a "redacted" screenshot could bring the content back.
final class RedactionTests: XCTestCase {

    /// A base image split into two halves of very different colours, so a redaction over the
    /// boundary has real detail to destroy.
    private func stripedImage(width: Int, height: Int) -> NSImage {
        let image = testImage(width: width, height: height) {
            NSColor.black.set()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            NSColor.white.set()
            // Fine stripes: the detail a redaction has to average away.
            for y in stride(from: 0, to: height, by: 4) {
                NSRect(x: 0, y: y, width: width, height: 2).fill()
            }
        }
        return image
    }

    private func redaction(over frame: CGRect) -> AnnotationObject {
        AnnotationObject(
            id: UUID(), kind: .blur, frame: frame,
            color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 1), strokeWidth: 1
        )
    }

    private func bitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return NSBitmapImageRep(cgImage: cg)
    }

    /// The core guarantee: the 4px stripe period under the redaction is gone from the export.
    ///
    /// Measured as the longest run of identical pixels down a line through the region. Pixelation
    /// makes whole blocks uniform, so runs are block-length; merely dimming the stripes (the old
    /// `alpha 0.9` overlay) leaves the pattern intact at reduced amplitude, so runs stay as short
    /// as the stripes themselves. Comparing neighbouring pixels would NOT separate the two — the
    /// old overlay scores *better* on that, because pixelation has legitimate steps at block
    /// boundaries.
    func testRedactionDestroysTheUnderlyingPatternRatherThanDimmingIt() throws {
        let base = stripedImage(width: 120, height: 120)
        let flattened = AnnotationRenderer.flatten(
            base: base, annotations: [redaction(over: CGRect(x: 20, y: 20, width: 80, height: 80))]
        )
        let out = try bitmap(flattened)

        var longestRun = 1
        var run = 1
        var previous = try XCTUnwrap(out.colorAt(x: 60, y: 40)).brightnessComponent
        for y in 41..<80 {
            let current = try XCTUnwrap(out.colorAt(x: 60, y: y)).brightnessComponent
            if abs(current - previous) < 0.01 {
                run += 1
                longestRun = max(longestRun, run)
            } else {
                run = 1
            }
            previous = current
        }
        // The source alternates every 2px, so anything preserving the pattern cannot exceed ~3.
        XCTAssertGreaterThanOrEqual(longestRun, 6, "redacted pixels should be uniform across a block")
    }

    func testRedactionIsFullyOpaque() throws {
        let base = stripedImage(width: 100, height: 100)
        let flattened = AnnotationRenderer.flatten(
            base: base, annotations: [redaction(over: CGRect(x: 10, y: 10, width: 80, height: 80))]
        )
        let out = try bitmap(flattened)

        for point in [(50, 50), (20, 20), (75, 75)] {
            let colour = try XCTUnwrap(out.colorAt(x: point.0, y: point.1))
            XCTAssertEqual(colour.alphaComponent, 1.0, accuracy: 0.01, "redaction must not be translucent")
        }
    }

    func testRedactionLeavesTheRestOfTheImageUntouched() throws {
        let base = stripedImage(width: 100, height: 100)
        let untouched = try bitmap(AnnotationRenderer.flatten(base: base, annotations: []))
        let redacted = try bitmap(AnnotationRenderer.flatten(
            base: base, annotations: [redaction(over: CGRect(x: 60, y: 60, width: 30, height: 30))]
        ))

        // Well clear of the redacted corner.
        for point in [(5, 5), (20, 40), (10, 90)] {
            let a = try XCTUnwrap(untouched.colorAt(x: point.0, y: point.1))
            let b = try XCTUnwrap(redacted.colorAt(x: point.0, y: point.1))
            XCTAssertEqual(a.brightnessComponent, b.brightnessComponent, accuracy: 0.02,
                           "pixels outside the redaction must be unchanged at \(point)")
        }
    }

    /// A redaction placed over an earlier annotation must cover that too — it samples the
    /// composited context, not the bare base image.
    func testRedactionCoversAnAnnotationDrawnBeneathIt() throws {
        let base = stripedImage(width: 100, height: 100)
        let solidBox = AnnotationObject(
            id: UUID(), kind: .rectangle, frame: CGRect(x: 30, y: 30, width: 40, height: 40),
            color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1), strokeWidth: 8
        )
        let flattened = AnnotationRenderer.flatten(
            base: base,
            annotations: [solidBox, redaction(over: CGRect(x: 20, y: 20, width: 60, height: 60))]
        )
        let out = try bitmap(flattened)

        // The red stroke ran through here; after redaction no pixel should still be saturated red.
        var maxRedness: CGFloat = 0
        for x in 25..<75 {
            for y in 25..<75 {
                if let c = out.colorAt(x: x, y: y) {
                    maxRedness = max(maxRedness, c.redComponent - max(c.greenComponent, c.blueComponent))
                }
            }
        }
        XCTAssertLessThan(maxRedness, 0.6, "the annotation underneath should have been pixelated too")
    }

    // MARK: - Pixelation helper

    func testPixelatedRegionClampsToTheImage() throws {
        let base = stripedImage(width: 50, height: 50)
        let cg = try XCTUnwrap(base.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let result = Pixelation.pixelatedRegion(of: cg, in: CGRect(x: 40, y: 40, width: 100, height: 100))
        XCTAssertNotNil(result, "a partly out-of-bounds region should still redact what exists")
    }

    func testPixelatedRegionReturnsNilOutsideTheImage() throws {
        let base = stripedImage(width: 50, height: 50)
        let cg = try XCTUnwrap(base.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertNil(Pixelation.pixelatedRegion(of: cg, in: CGRect(x: 200, y: 200, width: 10, height: 10)))
    }

    func testBlockSizeHasAFloorForSmallRegions() {
        XCTAssertGreaterThanOrEqual(Pixelation.blockSize(for: CGRect(x: 0, y: 0, width: 8, height: 8)), 10)
    }

    // MARK: - Redaction style

    /// Solid fill leaves nothing of the original, unlike pixelation which preserves coarse
    /// structure — this is the option to use when the content must be unrecoverable.
    func testSolidRedactionLeavesAUniformBlock() throws {
        let base = stripedImage(width: 100, height: 100)
        var solid = redaction(over: CGRect(x: 20, y: 20, width: 60, height: 60))
        solid.redactionStyle = .solid
        let out = try bitmap(AnnotationRenderer.flatten(base: base, annotations: [solid]))

        var brightnesses = Set<Int>()
        for x in 30..<70 {
            for y in 30..<70 {
                if let c = out.colorAt(x: x, y: y) {
                    brightnesses.insert(Int((c.brightnessComponent * 255).rounded()))
                }
            }
        }
        XCTAssertEqual(brightnesses.count, 1, "a solid block must be one flat colour throughout")
    }

    func testSolidRedactionIsOpaque() throws {
        let base = stripedImage(width: 60, height: 60)
        var solid = redaction(over: CGRect(x: 10, y: 10, width: 40, height: 40))
        solid.redactionStyle = .solid
        let out = try bitmap(AnnotationRenderer.flatten(base: base, annotations: [solid]))
        let colour = try XCTUnwrap(out.colorAt(x: 30, y: 30))
        XCTAssertEqual(colour.alphaComponent, 1.0, accuracy: 0.01)
    }

    /// A blur saved before the style existed has no `redactionStyle` key. Decoding must treat that
    /// as pixelate rather than failing — a failure would send the whole sidecar to quarantine and
    /// the capture would open with none of its annotations.
    func testASidecarWrittenBeforeStylesExistedStillDecodes() throws {
        let legacy = """
        [{"id":"0BE3E1F5-1B3E-4E2E-9E86-3D0F2B1C4A77","kind":{"blur":{}},        "frame":[[10,10],[40,40]],        "color":{"red":0,"green":0,"blue":0,"alpha":1},"strokeWidth":1}]
        """
        let decoded = try JSONDecoder().decode([AnnotationObject].self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.count, 1)
        XCTAssertNil(decoded[0].redactionStyle, "a missing style means the original pixelate behaviour")
    }

    func testStyleSurvivesARoundTrip() throws {
        var solid = redaction(over: CGRect(x: 0, y: 0, width: 10, height: 10))
        solid.redactionStyle = .solid
        let data = try JSONEncoder().encode([solid])
        let decoded = try JSONDecoder().decode([AnnotationObject].self, from: data)
        XCTAssertEqual(decoded.first?.redactionStyle, .solid)
    }
}
