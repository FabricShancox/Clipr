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
    private func export(_ html: String, timeout: TimeInterval = PDFGuideExporter.defaultTimeout,
                        locale: Locale = .current) async -> (URL, Error?) {
        let url = folder.appendingPathComponent("guide.pdf")
        let exporter = PDFGuideExporter(timeout: timeout)
        let done = expectation(description: "PDF export finished")
        let task = Task { @MainActor () -> Error? in
            defer { done.fulfill() }
            do {
                try await exporter.export(html: html, to: url, locale: locale)
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

    func testTallImagesWithCloseUpsNeverSplitSteps() async throws {
        let tall = testImage(width: 400, height: 1200) { NSColor.systemOrange.set(); NSRect(x: 0, y: 0, width: 400, height: 1200).fill() }
        let image = try XCTUnwrap(GuideImages.encode(try XCTUnwrap(tall.bitmap)))
        let steps = (1...30).map {
            GuideStep(number: $0, caption: "Heading \($0) end", appName: nil, imageSize: .full,
                      image: .file(URL(fileURLWithPath: "/unused.png")), zoom: .file(URL(fileURLWithPath: "/unused.png")))
        }
        var images = RenderedImages()
        for step in steps { images.steps[step.number] = image; images.zooms[step.number] = image }
        let html = HTMLGuideWriter.write(GuideDocument(title: "Tall", date: Date(), steps: steps), images: images, mode: .embedded)
        let (url, error) = await export(html)
        XCTAssertNil(error)
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        // One step per page at most (the title shares page 1): a split step would add pages.
        XCTAssertLessThanOrEqual(pdf.pageCount, 31)
        for number in 1...30 {
            let page = (0..<pdf.pageCount).first { pdf.page(at: $0)?.string?.contains("Heading \(number) end") == true }
            XCTAssertNotNil(page, "step \(number)")
        }
    }

    func testTimeoutReportsTimedOut() async throws {
        let (_, error) = await export(try guideHTML(steps: 3), timeout: 0.001)
        XCTAssertEqual(error as? PDFExportError, .timedOut)
    }

    func testCancelStopsAThirtyStepExportQuicklyAndLeavesNothing() async throws {
        let html = try guideHTML(steps: 30)
        let url = folder.appendingPathComponent("guide.pdf")
        let exporter = PDFGuideExporter()
        let done = expectation(description: "PDF export finished")
        let started = Date()
        let task = Task { @MainActor () -> Error? in
            defer { done.fulfill() }
            do {
                try await exporter.export(html: html, to: url)
                return nil
            } catch {
                return error
            }
        }
        while !exporter.isInFlight { await Task.yield() }
        exporter.cancel()
        await fulfillment(of: [done], timeout: 60)
        let error = await task.value
        XCTAssertEqual(error as? PDFExportError, .cancelled)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "well under the 30 s timeout")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        exporter.cancel() // a second cancel after finishing is harmless
    }

    func testCancelWhilePrintingFinishesCancelledAndLeavesNothing() async throws {
        let html = try guideHTML(steps: 30)
        let url = folder.appendingPathComponent("guide.pdf")
        var exporter: PDFGuideExporter? = PDFGuideExporter()
        let done = expectation(description: "PDF export finished")
        let task = Task { @MainActor [exporter] () -> Error? in
            defer { done.fulfill() }
            do {
                try await exporter?.export(html: html, to: url)
                return nil
            } catch {
                return error
            }
        }
        // Waits for the print to start; if this machine prints synchronously there's nothing to interrupt.
        let deadline = Date().addingTimeInterval(20)
        while exporter?.isInFlight == false { await Task.yield() }
        while exporter?.isInFlight == true, exporter?.isPrinting == false, Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let interruptedPrint = exporter?.isPrinting == true
        exporter?.cancel()
        exporter = nil // the caller lets go at once; a print still running must keep what it uses alive
        await fulfillment(of: [done], timeout: 60)
        let error = await task.value
        if interruptedPrint { XCTAssertEqual(error as? PDFExportError, .cancelled) }
        // Let a late print completion run, then nothing may be left behind.
        try await Task.sleep(nanoseconds: 500_000_000)
        if error != nil { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
    }

    func testPaperSizeFollowsLocale() {
        XCTAssertEqual(PDFGuideExporter.paperSize(for: Locale(identifier: "en_US")), NSSize(width: 612, height: 792))
        XCTAssertEqual(PDFGuideExporter.paperSize(for: Locale(identifier: "en_GB")), NSSize(width: 595.28, height: 841.89))
        XCTAssertEqual(PDFGuideExporter.paperSize(for: Locale(identifier: "de_DE")), NSSize(width: 595.28, height: 841.89))
        XCTAssertEqual(PDFGuideExporter.marginPoints, 51.02, accuracy: 0.01)
    }

    func testTimeoutLeavesNoDestinationFile() async throws {
        let (url, error) = await export(try guideHTML(steps: 3), timeout: 0.001)
        XCTAssertEqual(error as? PDFExportError, .timedOut)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testTimeoutLeavesExistingDestinationUnchanged() async throws {
        let url = folder.appendingPathComponent("guide.pdf")
        try Data("precious".utf8).write(to: url)
        let (_, error) = await export(try guideHTML(steps: 3), timeout: 0.001)
        XCTAssertEqual(error as? PDFExportError, .timedOut)
        XCTAssertEqual(try Data(contentsOf: url), Data("precious".utf8))
    }

    func testSuccessReplacesExistingFile() async throws {
        let url = folder.appendingPathComponent("guide.pdf")
        try Data("old".utf8).write(to: url)
        let (_, error) = await export(try guideHTML(steps: 3))
        XCTAssertNil(error)
        XCTAssertNotNil(PDFDocument(url: url))
    }

    func testSecondExportOnSameInstanceThrows() async throws {
        let exporter = PDFGuideExporter()
        let html = try guideHTML(steps: 1)
        try await exporter.export(html: html, to: folder.appendingPathComponent("a.pdf"))
        do {
            try await exporter.export(html: html, to: folder.appendingPathComponent("b.pdf"))
            XCTFail("expected alreadyUsed")
        } catch {
            XCTAssertEqual(error as? PDFExportError, .alreadyUsed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("b.pdf").path))
    }

    func testPageSizeFollowsLocale() async throws {
        for (id, expected) in [("en_GB", NSSize(width: 595.28, height: 841.89)), ("en_US", NSSize(width: 612, height: 792))] {
            let (url, error) = await export(try guideHTML(steps: 1), locale: Locale(identifier: id))
            XCTAssertNil(error)
            let bounds = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0)).bounds(for: .mediaBox)
            XCTAssertEqual(bounds.width, expected.width, accuracy: 1, id)
            XCTAssertEqual(bounds.height, expected.height, accuracy: 1, id)
            try FileManager.default.removeItem(at: url)
        }
    }
}
