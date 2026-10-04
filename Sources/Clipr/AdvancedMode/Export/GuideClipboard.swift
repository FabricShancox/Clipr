// Sources/Clipr/AdvancedMode/Export/GuideClipboard.swift
import AppKit

/// Puts the guide on the pasteboard as HTML (what web docs tools read) and RTF (what Pages, Word
/// and TextEdit read), both from the same embedded HTML the HTML export writes.
enum GuideClipboard {
    /// From the clipboard spike recorded in `docs/superpowers/checklists/advanced-mode-capture-manual.md`
    /// ("Export — clipboard spike"): true when any web docs tool dropped the pasted images.
    static let imagesMayBeDropped = true
    static let webAppNote = "Images may not paste into some web apps — use PDF or Markdown"

    /// Main thread only: AppKit's HTML import runs on WebKit. False if the pasteboard refused the HTML.
    @MainActor
    @discardableResult
    static func write(html: String, to pasteboard: NSPasteboard = .general) -> Bool {
        let rtf = rtfData(fromHTML: html)
        pasteboard.clearContents()
        var written = pasteboard.setString(html, forType: .html)
        if let rtf { written = pasteboard.setData(rtf, forType: .rtf) && written }
        return written
    }

    @MainActor
    static func rtfData(fromHTML html: String) -> Data? {
        guard let attributed = NSAttributedString(
            html: Data(html.utf8),
            options: [.characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) else { return nil }
        return attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])
    }
}
