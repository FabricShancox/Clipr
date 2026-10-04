// Tests/ClipprTests/PDFGuideExporterTests.swift
import XCTest
import Cocoa
import PDFKit
@testable import Clipr

/// WebKit printing runs on the main thread and calls back through the main run loop. The tests
/// are main-actor async: awaiting an XCTest expectation suspends the test without blocking the
/// main thread, so those callbacks get to run, and the expectation's timeout stops a hung export
/// failing the whole run (macOS has no `timeout` command to wrap `swift test` in).
@MainActor
final class PDFGuideExporterTests: XCTestCase {
    var folder: URL!

    override func setUp() async throws {
        // AppKit printing expects the shared application to exist; `swift test` doesn't create it.
        _ = NSApplication.shared
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func guideHTML(steps count: Int) throws -> String {
        let picture = testImage(width: 400, height: 225) {
            NSColor.systemTeal.set()
            NSRect(x: 0, y: 0, width: 400, height: 225).fill()
        }
        let image = try XCTUnwrap(GuideImages.encode(try XCTUnwrap(picture.bitmap)))
        let steps = (1...count).map {
            GuideStep(number: $0, caption: "Heading \($0) end", appName: "Safari", imageSize: .full,
                      image: .file(URL(fileURLWithPath: "/unused.png")), zoom: nil)
        }
        var images = RenderedImages()
        for step in steps { images.steps[step.number] = image }
        return HTMLGuideWriter.write(GuideDocument(title: "PDF test", date: Date(), steps: steps), images: images, mode: .embedded)
    }

    /// Runs one export and waits for it with an expectation, returning the file and any error.
    private func export(_ html: String, timeout: TimeInterval = PDFGuideExporter.defaultTimeout) async -> (URL, Error?) {
        let url = folder.appendingPathComponent("guide.pdf")
        let exporter = PDFGuideExporter(timeout: timeout)
        let done = expectation(description: "PDF export finished")
        let task = Task { @MainActor () -> Error? in
            defer { done.fulfill() }
            do {
                try await exporter.export(html: html, to: url)
                return nil
            } catch {
                return error
            }
        }
        await fulfillment(of: [done], timeout: 60)
        return (url, await task.value)
    }

    func testThreeStepsMakeAPDFWithEveryHeading() async throws {
        let (url, error) = await export(try guideHTML(steps: 3))
        XCTAssertNil(error)
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 1)
        let text = try XCTUnwrap(pdf.string)
        for number in 1...3 { XCTAssertTrue(text.contains("Heading \(number) end"), "step \(number)") }
    }

    func testThirtyStepsPaginate() async throws {
        let (url, error) = await export(try guideHTML(steps: 30))
        XCTAssertNil(error)
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        let text = try XCTUnwrap(pdf.string)
        for number in 1...30 { XCTAssertTrue(text.contains("Heading \(number) end"), "step \(number)") }
    }

    func testTimeoutReportsTimedOut() async throws {
        let (_, error) = await export(try guideHTML(steps: 3), timeout: 0.001)
        XCTAssertEqual(error as? PDFExportError, .timedOut)
    }

    func testPaperSizeFollowsLocale() {
        XCTAssertEqual(PDFGuideExporter.paperSize(for: Locale(identifier: "en_US")), NSSize(width: 612, height: 792))
        XCTAssertEqual(PDFGuideExporter.paperSize(for: Locale(identifier: "en_GB")), NSSize(width: 595.28, height: 841.89))
        XCTAssertEqual(PDFGuideExporter.paperSize(for: Locale(identifier: "de_DE")), NSSize(width: 595.28, height: 841.89))
        XCTAssertEqual(PDFGuideExporter.marginPoints, 51.02, accuracy: 0.01)
    }
}
