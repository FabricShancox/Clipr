// Tests/ClipprTests/GuideExportEndToEndTests.swift
import XCTest
import Cocoa
@testable import Clipr

/// A session on disk through the real pipeline: manifest -> document -> rendered images -> Markdown folder.
@MainActor
final class GuideExportEndToEndTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writePNG(width: Int, height: Int, noisy: Bool, to url: URL) throws {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        if noisy {
            var generator = SystemRandomNumberGenerator()
            for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255, using: &generator) }
        } else {
            for index in stride(from: 0, to: bytes.count, by: 4) { bytes[index + 2] = 200; bytes[index + 3] = 255 }
        }
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32))
        bytes.withUnsafeBufferPointer { rep.bitmapData!.update(from: $0.baseAddress!, count: bytes.count) }
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }

    func testMarkdownLinksMatchExportedFilesIncludingJPEGFallback() async throws {
        let session = root.appendingPathComponent("Session_2026-10-04_09-30-00")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try writePNG(width: 1400, height: 1000, noisy: true, to: session.appendingPathComponent("Step_01.png"))
        try writePNG(width: 400, height: 300, noisy: false, to: session.appendingPathComponent("Step_02.png"))
        try writePNG(width: 200, height: 200, noisy: false, to: session.appendingPathComponent("Step_02_zoom.png"))
        let created = Date()
        func record(_ file: String, zoom: String? = nil, size: ImageSize? = nil) -> StepRecord {
            StepRecord(id: UUID(), file: file, kind: .click, caption: "Do \(file)", clickPoint: nil,
                       zoomFile: zoom, appName: nil, capturedAt: created, imageSize: size)
        }
        try SessionManifestStore.save(SessionManifest(createdAt: created, steps: [
            record("Step_01.png"), record("Step_02.png", zoom: "Step_02_zoom.png", size: .small),
        ]), in: session)

        let manifest = SessionManifestStore.load(from: session)
        let options = ExportOptions(format: .markdown, title: "E2E", includeZoom: true)
        let doc = GuideDocument.make(manifest: manifest, folder: session, selection: [], options: options)
        let destination = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let warnings = try await GuideExporter(workRoot: root.appendingPathComponent("work")).export(doc, options: options, to: destination)
        XCTAssertEqual(warnings, [])

        let files = try FileManager.default.contentsOfDirectory(atPath: destination.appendingPathComponent("images").path).sorted()
        XCTAssertEqual(files, ["step-01.jpg", "step-02-zoom.png", "step-02.png"])
        let markdown = try String(contentsOf: destination.appendingPathComponent("guide.md"), encoding: .utf8)
        let regex = try NSRegularExpression(pattern: "images/[A-Za-z0-9._-]+")
        let links = regex.matches(in: markdown, range: NSRange(markdown.startIndex..., in: markdown))
            .map { String(markdown[Range($0.range, in: markdown)!]).replacingOccurrences(of: "images/", with: "") }
        XCTAssertEqual(links.sorted(), files)
        for link in links {
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("images/\(link)").path), link)
        }
    }
}
