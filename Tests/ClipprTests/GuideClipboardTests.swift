// Tests/ClipprTests/GuideClipboardTests.swift
import XCTest
import Cocoa
@testable import Clipr

@MainActor
final class GuideClipboardTests: XCTestCase {
    var pasteboard: NSPasteboard!

    override func setUp() async throws {
        // A private pasteboard, so the tests never touch what the user has copied.
        pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipprTests.\(UUID().uuidString)"))
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    private var doc: GuideDocument {
        GuideDocument(title: "Clip test", date: Date(), steps: [
            GuideStep(number: 1, caption: "Click **Save** now", appName: "Safari", imageSize: .full, image: .missing, zoom: nil),
        ])
    }

    private func payload(_ doc: GuideDocument, images: RenderedImages = RenderedImages()) throws -> GuideClipboard.Payload {
        try GuideClipboard.payload(doc, images: images)
    }

    func testWritesHTMLAndRTF() throws {
        let payload = try payload(doc)
        XCTAssertTrue(GuideClipboard.write(payload, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .html), HTMLGuideWriter.write(doc, images: RenderedImages(), mode: .embedded))
        let rtf = try XCTUnwrap(pasteboard.data(forType: .rtf))
        let text = try XCTUnwrap(NSAttributedString(rtf: rtf, documentAttributes: nil))
        XCTAssertTrue(text.string.contains("Clip test"))
        XCTAssertTrue(text.string.contains("Click Save now"))
        XCTAssertTrue(text.string.contains("Safari"))
        XCTAssertTrue(text.string.contains("Image unavailable"))
    }

    func testRTFKeepsBoldItalicAndCode() throws {
        let doc = GuideDocument(title: "T", date: Date(), steps: [
            GuideStep(number: 1, caption: "Click **Save** then *Done* in `cfg` [link](http://x)", appName: nil,
                      imageSize: .full, image: .missing, zoom: nil),
        ])
        let rtf = try XCTUnwrap(try payload(doc).rtf)
        let text = try XCTUnwrap(NSAttributedString(rtf: rtf, documentAttributes: nil))
        func font(_ word: String) throws -> NSFont {
            let range = (text.string as NSString).range(of: word)
            XCTAssertNotEqual(range.location, NSNotFound, word)
            return try XCTUnwrap(text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        }
        XCTAssertTrue(try font("Save").fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(try font("Done").fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertTrue(try font("cfg").fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertFalse(try font("Click").fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(text.string.contains("1. Click Save then Done in cfg link"), text.string)
        XCTAssertFalse(text.string.contains("http://x"))
    }

    func testReplacesWhatWasOnThePasteboard() throws {
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        GuideClipboard.write(try payload(doc), to: pasteboard)
        // The pasteboard may derive plain text from the RTF, but the old string must be gone.
        XCTAssertNotEqual(pasteboard.string(forType: .string), "old")
    }

    func testWritesRTFDWithTheStepImage() throws {
        let picture = testImage(width: 40, height: 30) {
            NSColor.systemTeal.set()
            NSRect(x: 0, y: 0, width: 40, height: 30).fill()
        }
        let image = try XCTUnwrap(GuideImages.encode(try XCTUnwrap(picture.bitmap)))
        let doc = GuideDocument(title: "Img", date: Date(), steps: [
            GuideStep(number: 1, caption: "Look", appName: nil, imageSize: .full, image: .file(URL(fileURLWithPath: "/unused.png")),
                      zoom: .file(URL(fileURLWithPath: "/unused-zoom.png"))),
        ])
        var images = RenderedImages()
        images.steps[1] = image
        images.zooms[1] = image
        XCTAssertTrue(GuideClipboard.write(try payload(doc, images: images), to: pasteboard))
        let rtfd = try XCTUnwrap(pasteboard.data(forType: .rtfd))
        let text = try XCTUnwrap(NSAttributedString(rtfd: rtfd, documentAttributes: nil))
        var attachments = 0
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if value != nil { attachments += 1 }
        }
        XCTAssertEqual(attachments, 2, "the step image and its close-up")
    }

    func testPicturesFitTheColumnAndAreNeverEnlarged() {
        XCTAssertEqual(GuideRichText.displaySize(pixelWidth: 1600, pixelHeight: 900, widthFraction: 1), CGSize(width: 600, height: 338))
        XCTAssertEqual(GuideRichText.displaySize(pixelWidth: 1600, pixelHeight: 800, widthFraction: 0.5), CGSize(width: 300, height: 150))
        XCTAssertEqual(GuideRichText.displaySize(pixelWidth: 40, pixelHeight: 30, widthFraction: 1), CGSize(width: 40, height: 30))
    }

    /// Counts how often the builder checks for cancellation; any thread.
    final class Checks: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        let stopAt: Int
        init(stopAt: Int) { self.stopAt = stopAt }
        func check() -> Bool {
            lock.lock(); defer { lock.unlock() }
            count += 1
            return count >= stopAt
        }
        var total: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    private func bigDoc(steps: Int) throws -> (GuideDocument, RenderedImages) {
        let picture = testImage(width: 400, height: 225) { NSColor.systemOrange.set(); NSRect(x: 0, y: 0, width: 400, height: 225).fill() }
        let image = try XCTUnwrap(GuideImages.encode(try XCTUnwrap(picture.bitmap)))
        let doc = GuideDocument(title: "Big", date: Date(), steps: (1...steps).map {
            GuideStep(number: $0, caption: "Step **\($0)**", appName: "Safari", imageSize: .full,
                      image: .file(URL(fileURLWithPath: "/unused.png")), zoom: nil)
        })
        var images = RenderedImages()
        for step in doc.steps { images.steps[step.number] = image }
        return (doc, images)
    }

    private nonisolated static func onMainThread() -> Bool { Thread.isMainThread }

    func testBuildsLargeGuideOffTheMainThread() async throws {
        let (doc, images) = try bigDoc(steps: 120)
        let (onMain, payload) = try await Task.detached {
            (Self.onMainThread(), try GuideClipboard.payload(doc, images: images))
        }.value
        XCTAssertFalse(onMain)
        let rtfd = try XCTUnwrap(payload.rtfd)
        let text = try XCTUnwrap(NSAttributedString(rtfd: rtfd, documentAttributes: nil))
        XCTAssertTrue(text.string.contains("120. Step 120"))
    }

    func testCancellingStopsTheBuildBetweenSteps() async throws {
        let (doc, images) = try bigDoc(steps: 120)
        let checks = Checks(stopAt: 5)
        do {
            _ = try await Task.detached {
                try GuideClipboard.payload(doc, images: images, isCancelled: { checks.check() })
            }.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertEqual(error as? GuideExportError, .cancelled)
        }
        XCTAssertEqual(checks.total, 5, "stopped as soon as cancellation was seen, not after all 120 steps")
    }
}
