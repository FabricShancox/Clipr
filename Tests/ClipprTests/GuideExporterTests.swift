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
    }, clipboard: @escaping @MainActor (GuideClipboard.Payload) -> Bool = { _ in true }) -> GuideExporter {
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
        var copied: GuideClipboard.Payload?
        let warnings = try await exporter(clipboard: { copied = $0; return true })
            .export(doc(), options: ExportOptions(format: .clipboard, title: "T"), to: nil)
        XCTAssertEqual(warnings.count, 2)
        let payload = try XCTUnwrap(copied)
        XCTAssertTrue(payload.html.contains("data:image/png;base64,"))
        XCTAssertNotNil(payload.rtf)
        XCTAssertNotNil(payload.rtfd)
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

    func testMarkdownFailedRestoreReportsAndKeepsTheBackup() throws {
        struct Boom: Error {}
        let output = root.appendingPathComponent("built")
        try FileManager.default.createDirectory(at: output.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data("new".utf8).write(to: output.appendingPathComponent("images/new.png"))
        try Data("g".utf8).write(to: output.appendingPathComponent("guide.md"))
        try FileManager.default.createDirectory(at: out.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: out.appendingPathComponent("images/mine.png"))
        XCTAssertThrowsError(try GuideExporter.moveIntoPlace(output, format: .markdown, destination: out,
                                                             placeGuide: { _, _ in throw Boom() },
                                                             restoreImages: { _, _ in throw Boom() })) { error in
            let restore = error as? ImagesRestoreError
            XCTAssertNotNil(restore, "\(error)")
            let backup = restore?.backup.lastPathComponent ?? ""
            XCTAssertTrue(backup.hasPrefix(".images-backup-"))
            let message = error.localizedDescription
            XCTAssertTrue(message.contains(out.appendingPathComponent(backup).path), message)
            XCTAssertEqual(GuideExportError.destinationNotWritable(message).localizedDescription,
                           "Couldn't write to the chosen location. \(message)")
            XCTAssertEqual(try? FileManager.default.contentsOfDirectory(atPath: out.appendingPathComponent(backup).path), ["mine.png"],
                           "the backup with the user's images is not deleted")
        }
    }

    func testStagesBesideTheDestinationWhenTheVolumeHasNoReplacementFolder() async throws {
        struct NoReplacement: Error {}
        var staged: URL?
        var exporter = exporter(pdf: { _, url in
            staged = url
            try Data("%PDF".utf8).write(to: url)
        })
        exporter.workRoot = nil
        exporter.replacementDirectory = { _ in throw NoReplacement() }
        let destination = out.appendingPathComponent("Guide.pdf")
        _ = try await exporter.export(doc(), options: ExportOptions(format: .pdf, title: "T"), to: destination)
        let folder = try XCTUnwrap(staged).deletingLastPathComponent()
        XCTAssertEqual(folder.deletingLastPathComponent().standardizedFileURL.path, out.standardizedFileURL.path)
        XCTAssertTrue(folder.lastPathComponent.hasPrefix(GuideExporter.stagingPrefix))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), ["Guide.pdf"], "staging folder removed")

        // Markdown stages inside the chosen folder (which may be a volume's root) and cleans up too.
        let folderOut = out.appendingPathComponent("md")
        try FileManager.default.createDirectory(at: folderOut, withIntermediateDirectories: true)
        _ = try await exporter.export(doc(), options: ExportOptions(format: .markdown, title: "T"), to: folderOut)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folderOut.path).sorted(), ["guide.md", "images"])
    }

    func testCopyAcrossNeverWritesTheFinalNameDirectly() throws {
        let built = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: built, withIntermediateDirectories: true)
        let file = built.appendingPathComponent("Guide.html")
        try Data("new".utf8).write(to: file)
        let destination = out.appendingPathComponent("Guide.html")
        try Data("old".utf8).write(to: destination)
        try GuideExporter.copyAcrossAndPlace(file, format: .html, destination: destination)
        XCTAssertEqual(try Data(contentsOf: destination), Data("new".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path), ["Guide.html"])

        let guide = built.appendingPathComponent("Guide")
        try FileManager.default.createDirectory(at: guide.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data("g".utf8).write(to: guide.appendingPathComponent("guide.md"))
        try GuideExporter.copyAcrossAndPlace(guide, format: .markdown, destination: out)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: out.path).sorted(), ["Guide.html", "guide.md", "images"])
    }

    func testCancellingDuringRealPDFStopsQuicklyAndLeavesNothing() async throws {
        _ = NSApplication.shared
        let picture = testImage(width: 400, height: 225) { NSColor.systemTeal.set(); NSRect(x: 0, y: 0, width: 400, height: 225).fill() }
        let image = try XCTUnwrap(GuideImages.encode(try XCTUnwrap(picture.bitmap)))
        var printing = false
        let exporter = GuideExporter(renderImage: { _, _ in GuideImageRender(image: image, sidecarDamaged: false) },
                                     writePDF: { html, url in
                                         printing = true
                                         try await GuideExporter.printPDF(html, to: url)
                                     }, workRoot: work)
        let destination = out.appendingPathComponent("Guide.pdf")
        let big = doc(sizes: Array(repeating: .full, count: 30))
        let done = expectation(description: "export finished")
        let started = Date()
        let task = Task { @MainActor () -> Error? in
            defer { done.fulfill() }
            do {
                _ = try await exporter.export(big, options: ExportOptions(format: .pdf, title: "T"), to: destination)
                return nil
            } catch {
                return error
            }
        }
        while !printing { await Task.yield() }
        task.cancel()
        await fulfillment(of: [done], timeout: 60)
        let error = await task.value
        XCTAssertEqual(error as? GuideExportError, .cancelled)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10, "well under the 30 s PDF timeout")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try workIsEmpty())
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
