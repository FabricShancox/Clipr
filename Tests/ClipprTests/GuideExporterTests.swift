// Tests/ClipprTests/GuideExporterTests.swift
import XCTest
import Cocoa
@testable import Clipr

@MainActor
final class GuideExporterTests: XCTestCase {
    var root: URL!
    var work: URL!
    var out: URL!

    /// Counts render calls from the background render loop; read only after the export returns.
    final class Calls: @unchecked Sendable {
        var widths: [Int] = []
    }

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        work = root.appendingPathComponent("work")
        out = root.appendingPathComponent("out")
        for folder in [work!, out!] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    }

    override func tearDown() async throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: out.path)
        try? FileManager.default.removeItem(at: root)
    }

    private let png = GuideImage(data: Data([0x89, 0x50, 0x4E, 0x47]), pixelWidth: 10, pixelHeight: 5, kind: .png)

    private func doc(sizes: [ImageSize] = [.small, .full, .full], zoomOnFirst: Bool = false) -> GuideDocument {
        let somewhere = GuideImageRef.file(URL(fileURLWithPath: "/unused.png"))
        return GuideDocument(title: "T", date: Date(), steps: sizes.enumerated().map { index, size in
            GuideStep(number: index + 1, caption: "Heading \(index + 1)", appName: nil, imageSize: size,
                      image: somewhere, zoom: zoomOnFirst && index == 0 ? somewhere : nil)
        })
    }

    /// Step 2's image is missing and step 3's sidecar is damaged; every other render succeeds.
    private func exporter(calls: Calls = Calls(), pdf: @escaping @MainActor (String, URL) async throws -> Void = { _, url in
        try Data("%PDF".utf8).write(to: url)
    }, clipboard: @escaping @MainActor (String) -> Bool = { _ in true }) -> GuideExporter {
        let image = png
        return GuideExporter(
            renderImage: { _, width in
                calls.widths.append(width)
                switch calls.widths.count {
                case 2: return GuideImageRender(image: nil, sidecarDamaged: false)
                case 3: return GuideImageRender(image: image, sidecarDamaged: true)
                default: return GuideImageRender(image: image, sidecarDamaged: false)
                }
            },
            writePDF: pdf, copyToClipboard: clipboard, workRoot: work
        )
    }

    private func workIsEmpty() throws -> Bool {
        try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty
    }

    func testHTMLExportWritesFileAndReportsWarnings() async throws {
        let destination = out.appendingPathComponent("Guide.html")
        let warnings = try await exporter().export(doc(), options: ExportOptions(format: .html, title: "T"), to: destination)
        XCTAssertEqual(warnings, [.missingImage(step: 2), .damagedAnnotations(step: 3)])
        let html = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(html.contains("Image unavailable"))
        XCTAssertTrue(try workIsEmpty())
    }

    func testRequestsWidthPerFormat() async throws {
        let htmlCalls = Calls()
        _ = try await exporter(calls: htmlCalls).export(doc(zoomOnFirst: true), options: ExportOptions(format: .html, title: "T"),
                                                        to: out.appendingPathComponent("a.html"))
        XCTAssertEqual(htmlCalls.widths, [640, 480, 1600, 1600], "step 1, its close-up, steps 2 and 3")
        let gifCalls = Calls()
        _ = try await exporter(calls: gifCalls).export(doc(zoomOnFirst: true), options: ExportOptions(format: .gif, title: "T"),
                                                       to: out.appendingPathComponent("a.gif"))
        XCTAssertEqual(gifCalls.widths, [1000, 1000, 1000], "GIF frames use the canvas width and skip close-ups")
    }

    func testReplacesExistingFileAtDestination() async throws {
        let destination = out.appendingPathComponent("Guide.html")
        try Data("old".utf8).write(to: destination)
        _ = try await exporter().export(doc(), options: ExportOptions(format: .html, title: "T"), to: destination)
        XCTAssertTrue(try String(contentsOf: destination, encoding: .utf8).hasPrefix("<!doctype html>"))
    }

    func testMarkdownReplacesGuideAndImagesInChosenFolder() async throws {
        try Data("old".utf8).write(to: out.appendingPathComponent("guide.md"))
        try FileManager.default.createDirectory(at: out.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: out.appendingPathComponent("images/stale.png"))
        _ = try await exporter().export(doc(), options: ExportOptions(format: .markdown, title: "T"), to: out)
        XCTAssertTrue(try String(contentsOf: out.appendingPathComponent("guide.md"), encoding: .utf8).hasPrefix("# T\n"))
        let images = try FileManager.default.contentsOfDirectory(atPath: out.appendingPathComponent("images").path).sorted()
        XCTAssertEqual(images, ["step-01.png", "step-03.png"])
        XCTAssertTrue(try workIsEmpty())
    }

    func testCancelStopsBeforeNextStepAndLeavesNothing() async throws {
        let calls = Calls()
        let destination = out.appendingPathComponent("Guide.html")
        do {
            _ = try await exporter(calls: calls).export(doc(), options: ExportOptions(format: .html, title: "T"), to: destination,
                                                        isCancelled: { !calls.widths.isEmpty })
            XCTFail("expected cancellation")
        } catch {
            XCTAssertEqual(error as? GuideExportError, .cancelled)
        }
        XCTAssertEqual(calls.widths.count, 1, "stopped before the second step")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try workIsEmpty())
    }

    func testCancellingTheTaskCancelsTheExport() async throws {
        let destination = out.appendingPathComponent("Guide.html")
        let exporter = exporter()
        let task = Task { @MainActor in
            try await exporter.export(doc(), options: ExportOptions(format: .html, title: "T"), to: destination)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertEqual(error as? GuideExportError, .cancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testUnwritableDestinationLeavesNothing() async throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: out.path)
        let destination = out.appendingPathComponent("Guide.html")
        do {
            _ = try await exporter().export(doc(), options: ExportOptions(format: .html, title: "T"), to: destination)
            XCTFail("expected a failure")
        } catch {
            guard case .destinationNotWritable = error as? GuideExportError else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try workIsEmpty())
    }

    func testPDFFailureSuggestsHTMLAndLeavesNothing() async throws {
        struct Boom: Error {}
        let destination = out.appendingPathComponent("Guide.pdf")
        do {
            _ = try await exporter(pdf: { _, _ in throw Boom() }).export(doc(), options: ExportOptions(format: .pdf, title: "T"), to: destination)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? GuideExportError, .pdfFailed)
            XCTAssertEqual(error.localizedDescription, "Couldn't create the PDF. Try exporting as HTML instead.")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try workIsEmpty())
    }

    func testClipboardGetsEmbeddedHTMLAndNeedsNoDestination() async throws {
        var copied: String?
        let warnings = try await exporter(clipboard: { copied = $0; return true })
            .export(doc(), options: ExportOptions(format: .clipboard, title: "T"), to: nil)
        XCTAssertEqual(warnings.count, 2)
        XCTAssertTrue(try XCTUnwrap(copied).contains("data:image/png;base64,"))
    }

    func testRenderProgressReachesOne() throws {
        var fractions: [Double] = []
        _ = try GuideExporter.renderImages(doc(), format: .html, render: { _, _ in GuideImageRender(image: nil, sidecarDamaged: false) },
                                           isCancelled: { false }, progress: { fractions.append($0) })
        XCTAssertEqual(fractions, [1.0 / 3, 2.0 / 3, 1])
    }

    func testDefaultWorkRootExportsAndLeavesNoWorkFolder() async throws {
        var exporter = exporter()
        exporter.workRoot = nil
        let destination = out.appendingPathComponent("Guide.html")
        _ = try await exporter.export(doc(), options: ExportOptions(format: .html, title: "T"), to: destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), ["Guide.html"])
    }

    func testMarkdownGuideFailureRestoresOldImages() throws {
        struct Boom: Error {}
        let output = root.appendingPathComponent("built")
        try FileManager.default.createDirectory(at: output.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data("new".utf8).write(to: output.appendingPathComponent("images/new.png"))
        try Data("g".utf8).write(to: output.appendingPathComponent("guide.md"))
        try FileManager.default.createDirectory(at: out.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: out.appendingPathComponent("images/mine.png"))
        XCTAssertThrowsError(try GuideExporter.moveIntoPlace(output, format: .markdown, destination: out, placeGuide: { _, _ in throw Boom() }))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path).sorted(), ["images"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.appendingPathComponent("images").path), ["mine.png"])
    }

    func testWarningSummary() {
        XCTAssertNil(GuideWarning.summary([]))
        XCTAssertEqual(GuideWarning.summary([.missingImage(step: 2), .missingImage(step: 5), .damagedAnnotations(step: 3)]),
                       "Steps 2, 5: image unavailable — exported with a placeholder.\nStep 3: annotations couldn't be read — exported without them.")
    }

    func testFailedCloseUpWarnsAndIsDropped() async throws {
        let image = png
        let somewhere = GuideImageRef.file(URL(fileURLWithPath: "/unused.png"))
        let zoomRef = GuideImageRef.file(URL(fileURLWithPath: "/unused-zoom.png"))
        let step = GuideStep(number: 1, caption: "A", appName: nil, imageSize: .full, image: somewhere, zoom: zoomRef)
        let exporter = GuideExporter(renderImage: { ref, _ in
            ref == zoomRef ? GuideImageRender(image: nil, sidecarDamaged: false) : GuideImageRender(image: image, sidecarDamaged: false)
        }, workRoot: work)
        let destination = out.appendingPathComponent("Guide.html")
        let warnings = try await exporter.export(GuideDocument(title: "T", date: Date(), steps: [step]),
                                                 options: ExportOptions(format: .html, title: "T", includeZoom: true), to: destination)
        XCTAssertEqual(warnings, [.missingCloseUp(step: 1)])
        XCTAssertFalse(try String(contentsOf: destination, encoding: .utf8).contains("Image unavailable"))
        XCTAssertEqual(GuideWarning.summary(warnings), "Step 1: close-up couldn't be rendered — exported without it.")
    }
}
