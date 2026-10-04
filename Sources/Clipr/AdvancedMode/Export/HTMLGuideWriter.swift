// Sources/Clipr/AdvancedMode/Export/HTMLGuideWriter.swift
import Foundation

/// The one guide template behind HTML, PDF and the clipboard. Light theme and the system font
/// stack only, so it looks the same printed, opened in a browser and pasted into a docs tool.
enum HTMLGuideWriter {
    /// A close-up sits beside its step image at this share of the content width.
    static let zoomWidthPercent = 30

    static func write(_ doc: GuideDocument, images: RenderedImages, mode: HTMLImageMode) -> String {
        var html = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(contentSecurityPolicy(for: mode))
        <title>\(CaptionMarkup.escapeHTML(doc.title))</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <main class="guide">
        <header><h1>\(CaptionMarkup.escapeHTML(doc.title))</h1><p class="meta">\(CaptionMarkup.escapeHTML(doc.subtitle))</p></header>

        """
        for step in doc.steps {
            html += stepHTML(step, images: images, mode: mode)
        }
        html += "</main>\n</body>\n</html>\n"
        return html
    }

    /// No script, network or frames: only inline styles and data-URI images. Linked mode points at
    /// files beside the HTML (file:// has no reliable `'self'`), so it carries no policy.
    static func contentSecurityPolicy(for mode: HTMLImageMode) -> String {
        guard mode == .embedded else { return "" }
        return "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline'\">"
    }

    private static func stepHTML(_ step: GuideStep, images: RenderedImages, mode: HTMLImageMode) -> String {
        let number = step.number
        var html = "<section class=\"step\">\n"
        html += "<h2><span class=\"num\">\(number)</span><span class=\"caption\">"
        html += CaptionMarkup.html(step.caption, fallbackNumber: number)
        html += "</span></h2>\n"
        if let app = step.appName {
            html += "<p class=\"app\">\(CaptionMarkup.escapeHTML(app))</p>\n"
        }
        html += "<div class=\"figure\">\n"
        html += imageHTML(images.steps[number], step: number, zoom: false, alt: "Step \(number)",
                          width: step.imageSize.widthPercent, mode: mode)
        // A close-up that failed to render is left out (the exporter warns), not shown as a placeholder.
        if step.zoom != nil, let zoom = images.zooms[number] {
            html += imageHTML(zoom, step: number, zoom: true, alt: "Step \(number) close-up",
                              width: zoomWidthPercent, mode: mode)
        }
        html += "</div>\n</section>\n"
        return html
    }

    private static func imageHTML(_ image: GuideImage?, step: Int, zoom: Bool, alt: String, width: Int, mode: HTMLImageMode) -> String {
        let role = zoom ? "zoom" : "shot"
        guard let image else {
            return "<div class=\"\(role) missing\" style=\"width:\(width)%\">Image unavailable</div>\n"
        }
        let src: String
        switch mode {
        case .embedded:
            src = "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
        case .linked(let prefix):
            src = CaptionMarkup.escapeHTML(prefix + GuideImage.fileName(step: step, zoom: zoom, kind: image.kind))
        }
        return "<img class=\"\(role)\" src=\"\(src)\" alt=\"\(alt)\" style=\"width:\(width)%;max-width:\(image.pixelWidth)px;--w:\(width)%\">\n"
    }

    /// `break-inside: avoid` keeps each step on one page when WebKit prints the PDF; the print-only
    /// `max-height` shrinks a tall image to fit the page instead of letting the step split.
    static let css = """
    :root { color-scheme: light; }
    body { margin: 0; background: #fff; color: #1d1d1f; font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
    .guide { max-width: 860px; margin: 0 auto; padding: 32px 24px; }
    h1 { overflow-wrap: anywhere; font-size: 28px; line-height: 1.2; margin: 0 0 4px; }
    .meta { overflow-wrap: anywhere; color: #6e6e73; margin: 0 0 28px; }
    .step { break-inside: avoid; page-break-inside: avoid; margin: 0 0 32px; }
    .step h2 { overflow-wrap: anywhere; display: flex; align-items: baseline; gap: 10px; font-size: 18px; font-weight: 400; margin: 0 0 2px; }
    .num { flex: none; display: inline-flex; align-items: center; justify-content: center; width: 26px; height: 26px; border-radius: 50%; background: #0a84ff; color: #fff; font-size: 14px; font-weight: 600; }
    .app { overflow-wrap: anywhere; color: #8e8e93; font-size: 12px; margin: 0 0 8px 36px; }
    .figure { display: flex; flex-wrap: wrap; gap: 12px; align-items: flex-start; margin-top: 8px; }
    .figure > * { flex: none; box-sizing: border-box; max-width: 100%; border: 1px solid #d2d2d7; border-radius: 6px; }
    .figure img { display: block; height: auto; }
    .missing { display: flex; align-items: center; justify-content: center; min-height: 120px; background: #f2f2f4; color: #8e8e93; }
    code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em; background: #f2f2f4; padding: 1px 4px; border-radius: 4px; }
    @media print {
      .guide { max-width: none; padding: 0; }
      .figure { flex-wrap: nowrap; }
      .figure > * { flex: 0 1 auto; min-width: 0; }
      .figure img { width: auto !important; max-width: var(--w); max-height: 215mm; }
    }
    """
}
