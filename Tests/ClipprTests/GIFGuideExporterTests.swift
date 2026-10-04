// Tests/ClipprTests/GIFGuideExporterTests.swift
import XCTest
import Cocoa
import ImageIO
@testable import Clipr

final class GIFGuideExporterTests: XCTestCase {
    var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func solid(width: Int, height: Int) throws -> GuideImage {
        let image = testImage(width: width, height: height) {
            NSColor.systemBlue.set()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
        return try XCTUnwrap(GuideImages.encode(try XCTUnwrap(image.bitmap)))
    }

    /// Three steps: a wide image, a tall one, and one whose image is missing.
    private func export(frameSeconds: Double) throws {
        let somewhere = GuideImageRef.file(URL(fileURLWithPath: "/unused.png"))
        let doc = GuideDocument(title: "GIF", date: Date(), steps: [
            GuideStep(number: 1, caption: "Click **Save**", appName: nil, imageSize: .full, image: somewhere, zoom: nil),
            GuideStep(number: 2, caption: nil, appName: nil, imageSize: .small, image: somewhere, zoom: nil),
            GuideStep(number: 3, caption: "Done", appName: nil, imageSize: .full, image: .missing, zoom: nil),
        ])
        let images = RenderedImages(steps: [1: try solid(width: 1200, height: 600), 2: try solid(width: 800, height: 800)])
        try GIFGuideExporter.export(doc, images: images, frameSeconds: frameSeconds, to: url)
    }

    private func source() throws -> CGImageSource {
        try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    }

    private func delay(of frame: Int, in source: CGImageSource) throws -> Double {
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [CFString: Any])
        let gif = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        return try XCTUnwrap((gif[kCGImagePropertyGIFUnclampedDelayTime] ?? gif[kCGImagePropertyGIFDelayTime]) as? Double)
    }

    func testOneFramePerStepOnAConstantCanvas() throws {
        try export(frameSeconds: 2)
        let source = try source()
        XCTAssertEqual(CGImageSourceGetCount(source), 3)
        for index in 0..<3 {
            let frame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, nil))
            // Widest 1200 → capped at 1000; the 800×800 image is the tallest at that width.
            XCTAssertEqual(frame.width, 1000)
            XCTAssertEqual(frame.height, 800 + GIFGuideExporter.captionBandHeight)
        }
    }

    func testFrameDelayAndLoopForever() throws {
        try export(frameSeconds: 2)
        let source = try source()
        for index in 0..<3 { XCTAssertEqual(try delay(of: index, in: source), 2, accuracy: 0.01) }
        let properties = try XCTUnwrap(CGImageSourceCopyProperties(source, nil) as? [CFString: Any])
        let gif = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        XCTAssertEqual(gif[kCGImagePropertyGIFLoopCount] as? Int, 0)
    }

    func testFrameTimeIsClampedToOneToFiveSeconds() throws {
        try export(frameSeconds: 9)
        XCTAssertEqual(try delay(of: 0, in: source()), 5, accuracy: 0.01)
        try export(frameSeconds: 0.2)
        XCTAssertEqual(try delay(of: 0, in: source()), 1, accuracy: 0.01)
    }

    func testCanvasSizeLimits() throws {
        XCTAssertEqual(GIFGuideExporter.canvasSize(for: [nil]),
                       CGSize(width: 1000, height: GIFGuideExporter.placeholderHeight + GIFGuideExporter.captionBandHeight))
        XCTAssertEqual(GIFGuideExporter.canvasSize(for: [try solid(width: 300, height: 100)]),
                       CGSize(width: 480, height: 100 + GIFGuideExporter.captionBandHeight))
    }

    private func bitmap(_ frame: CGImage) -> NSBitmapImageRep { NSBitmapImageRep(cgImage: frame) }

    private func brightness(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> CGFloat {
        try XCTUnwrap(rep.colorAt(x: x, y: y)).brightnessComponent
    }

    func testSmallImageIsCentredNotEnlarged() throws {
        let canvas = GIFGuideExporter.canvasSize(for: [try solid(width: 300, height: 100)])
        let frame = try XCTUnwrap(GIFGuideExporter.renderFrame(try solid(width: 300, height: 100), caption: "", canvas: canvas))
        let rep = bitmap(frame)
        XCTAssertEqual(rep.pixelsWide, 480)
        // Image area is 100 px tall, so the image fills it; 300 px wide on 480 leaves 90 px each side.
        let blue = try XCTUnwrap(rep.colorAt(x: 240, y: 50))
        XCTAssertGreaterThan(blue.blueComponent, 0.8)
        XCTAssertLessThan(blue.redComponent, 0.5, "image pixel, not margin")
        XCTAssertEqual(try brightness(rep, 40, 50), 1, accuracy: 0.01, "left margin white")
        XCTAssertEqual(try brightness(rep, 440, 50), 1, accuracy: 0.01, "right margin white")
        XCTAssertLessThan(try XCTUnwrap(rep.colorAt(x: 100, y: 50)).redComponent, 0.5, "image starts at x=90")
    }

    func testCaptionBandIsLightGreyWithText() throws {
        let canvas = CGSize(width: 480, height: 100 + GIFGuideExporter.captionBandHeight)
        let frame = try XCTUnwrap(GIFGuideExporter.renderFrame(try solid(width: 300, height: 100), caption: "Click Save", canvas: canvas))
        let rep = bitmap(frame)
        let bandTop = 100
        XCTAssertEqual(try brightness(rep, 4, bandTop + 4), 0.96, accuracy: 0.02)
        var distinct = Set<Int>()
        for y in bandTop..<(bandTop + GIFGuideExporter.captionBandHeight) {
            for x in 0..<480 { distinct.insert(Int(try brightness(rep, x, y) * 50)) }
        }
        XCTAssertGreaterThan(distinct.count, 1, "caption text drawn over the band")
        // Without a caption the band is uniform.
        let empty = bitmap(try XCTUnwrap(GIFGuideExporter.renderFrame(try solid(width: 300, height: 100), caption: "", canvas: canvas)))
        var emptyValues = Set<Int>()
        for y in bandTop..<(bandTop + GIFGuideExporter.captionBandHeight) {
            for x in stride(from: 0, to: 480, by: 7) { emptyValues.insert(Int(try brightness(empty, x, y) * 50)) }
        }
        XCTAssertEqual(emptyValues.count, 1)
    }

    func testMissingImageDrawsPlaceholder() throws {
        let canvas = CGSize(width: 1000, height: GIFGuideExporter.placeholderHeight + GIFGuideExporter.captionBandHeight)
        let frame = try XCTUnwrap(GIFGuideExporter.renderFrame(nil, caption: "Done", canvas: canvas))
        let rep = bitmap(frame)
        XCTAssertEqual(try brightness(rep, 500, 10), 1, accuracy: 0.01, "white margin around the box")
        XCTAssertEqual(try brightness(rep, 40, 40), 0.95, accuracy: 0.02, "light grey placeholder box")
    }

    func testTallImageIsScaledToKeepCanvasWithinMaxHeight() throws {
        let tall = try solid(width: 400, height: 5000)
        let canvas = GIFGuideExporter.canvasSize(for: [tall])
        XCTAssertLessThanOrEqual(canvas.height, CGFloat(GIFGuideExporter.maxCanvasHeight))
        let fitted = GIFGuideExporter.fittedSize(tall, width: Int(canvas.width), maxHeight: Int(canvas.height) - GIFGuideExporter.captionBandHeight)
        XCTAssertEqual(fitted.height, GIFGuideExporter.maxCanvasHeight - GIFGuideExporter.captionBandHeight)
        XCTAssertEqual(Double(fitted.width) / Double(fitted.height), 400.0 / 5000.0, accuracy: 0.002, "aspect kept")
        let frame = try XCTUnwrap(GIFGuideExporter.renderFrame(tall, caption: "Tall", canvas: canvas))
        XCTAssertEqual(frame.height, Int(canvas.height))
    }
}
