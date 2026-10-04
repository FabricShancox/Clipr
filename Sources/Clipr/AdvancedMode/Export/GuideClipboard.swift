import AppKit

/// Puts the guide on the pasteboard as HTML (what web docs tools read), RTF and RTFD (what Pages,
/// Word and TextEdit read). The rich text is built straight from the document — never through
/// AppKit's HTML importer, which runs WebKit synchronously on the main thread — so everything but
/// the pasteboard write happens off the main thread and can stop between steps.
enum GuideClipboard {
    /// From the clipboard spike recorded in `docs/superpowers/checklists/advanced-mode-capture-manual.md`
    /// ("Export — clipboard spike"): true when any web docs tool dropped the pasted images.
    static let imagesMayBeDropped = true
    static let webAppNote = "Images may not paste into some web apps — use PDF or Markdown"

    /// Everything that goes on the pasteboard, ready to write.
    struct Payload: Sendable {
        let html: String
        let rtf: Data?
        /// Plain RTF has no inline pictures; RTFD carries the guide's images to apps that read it.
        let rtfd: Data?
    }

    /// Any thread. Throws `GuideExportError.cancelled` once `isCancelled` returns true (checked
    /// between steps and between the stages).
    static func payload(_ doc: GuideDocument, images: RenderedImages,
                        isCancelled: () -> Bool = { false }) throws -> Payload {
        let html = HTMLGuideWriter.write(doc, images: images, mode: .embedded)
        if isCancelled() { throw GuideExportError.cancelled }
        let text = try GuideRichText.build(doc, images: images, isCancelled: isCancelled)
        let range = NSRange(location: 0, length: text.length)
        let rtf = text.rtf(from: range, documentAttributes: [:])
        if isCancelled() { throw GuideExportError.cancelled }
        let rtfd = text.rtfd(from: range, documentAttributes: [:])
        if isCancelled() { throw GuideExportError.cancelled }
        return Payload(html: html, rtf: rtf, rtfd: rtfd)
    }

    /// Main thread: only the pasteboard write. False if the pasteboard refused the HTML.
    @MainActor
    @discardableResult
    static func write(_ payload: Payload, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        var written = pasteboard.setString(payload.html, forType: .html)
        if let rtf = payload.rtf { written = pasteboard.setData(rtf, forType: .rtf) && written }
        if let rtfd = payload.rtfd { written = pasteboard.setData(rtfd, forType: .rtfd) && written }
        return written
    }
}
