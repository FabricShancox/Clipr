import AppKit

/// The guide as an attributed string for RTF/RTFD, laid out like the HTML template: title, date
/// line, then each step's numbered caption, app name and picture(s). Fixed light-theme colours
/// and explicit fonts only, so it is safe to build off the main thread.
enum GuideRichText {
    /// The content column pictures are sized against, in points.
    static let columnWidth: CGFloat = 600

    private static let ink = NSColor(srgbRed: 0x1d / 255, green: 0x1d / 255, blue: 0x1f / 255, alpha: 1)
    private static let secondary = NSColor(srgbRed: 0x6e / 255, green: 0x6e / 255, blue: 0x73 / 255, alpha: 1)
    private static let tertiary = NSColor(srgbRed: 0x8e / 255, green: 0x8e / 255, blue: 0x93 / 255, alpha: 1)

    static func build(_ doc: GuideDocument, images: RenderedImages,
                      isCancelled: () -> Bool = { false }) throws -> NSAttributedString {
        let out = NSMutableAttributedString()
        out.append(line(CaptionMarkup.stripBidi(doc.title), font: .boldSystemFont(ofSize: 28), color: ink, spacingAfter: 4))
        out.append(line(doc.subtitle, font: .systemFont(ofSize: 15), color: secondary, spacingAfter: 24))
        for step in doc.steps {
            if isCancelled() { throw GuideExportError.cancelled }
            out.append(heading(step))
            if let app = step.appName {
                out.append(line(CaptionMarkup.stripBidi(app), font: .systemFont(ofSize: 12), color: tertiary, spacingAfter: 6))
            }
            out.append(figure(step, images: images))
        }
        return out
    }

    /// "N. " plus the caption with its bold, italic and code kept; "Step N" when it has none.
    private static func heading(_ step: GuideStep) -> NSAttributedString {
        let size: CGFloat = 18
        let text = NSMutableAttributedString(string: "\(step.number). ", attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: ink,
        ])
        let spans = CaptionMarkup.spans(step.caption)
        if spans.isEmpty {
            text.append(NSAttributedString(string: "Step \(step.number)", attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: ink]))
        }
        for span in spans {
            text.append(NSAttributedString(string: span.text, attributes: [
                .font: font(for: span, size: size), .foregroundColor: ink,
            ]))
        }
        text.append(NSAttributedString(string: "\n"))
        text.addAttribute(.paragraphStyle, value: paragraph(spacingAfter: 2), range: NSRange(location: 0, length: text.length))
        return text
    }

    static func font(for span: CaptionMarkup.Span, size: CGFloat) -> NSFont {
        let base = span.code
            ? NSFont.monospacedSystemFont(ofSize: size * 0.9, weight: span.bold ? .bold : .regular)
            : NSFont.systemFont(ofSize: size, weight: span.bold ? .bold : .regular)
        var traits = base.fontDescriptor.symbolicTraits
        if span.bold { traits.insert(.bold) }
        if span.italic { traits.insert(.italic) }
        guard traits != base.fontDescriptor.symbolicTraits else { return base }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: base.pointSize) ?? base
    }

    /// The step picture, then its close-up when there is one, as one paragraph.
    private static func figure(_ step: GuideStep, images: RenderedImages) -> NSAttributedString {
        let text = NSMutableAttributedString()
        if let image = images.steps[step.number] {
            text.append(attachment(image, step: step.number, zoom: false, widthFraction: step.imageSize.widthFraction))
        } else {
            text.append(NSAttributedString(string: "Image unavailable", attributes: [
                .font: NSFont.systemFont(ofSize: 15), .foregroundColor: tertiary,
            ]))
        }
        // A close-up that failed to render is left out (the exporter warns), as in the HTML.
        if step.zoom != nil, let zoom = images.zooms[step.number] {
            text.append(NSAttributedString(string: " "))
            text.append(attachment(zoom, step: step.number, zoom: true,
                                   widthFraction: CGFloat(HTMLGuideWriter.zoomWidthPercent) / 100))
        }
        text.append(NSAttributedString(string: "\n"))
        text.addAttribute(.paragraphStyle, value: paragraph(spacingAfter: 28), range: NSRange(location: 0, length: text.length))
        return text
    }

    /// A file-wrapper attachment (so RTFD carries the encoded image as is), sized to its share of
    /// the column and never wider than its own pixels.
    private static func attachment(_ image: GuideImage, step: Int, zoom: Bool, widthFraction: CGFloat) -> NSAttributedString {
        let wrapper = FileWrapper(regularFileWithContents: image.data)
        wrapper.preferredFilename = GuideImage.fileName(step: step, zoom: zoom, kind: image.kind)
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        let size = displaySize(pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight, widthFraction: widthFraction)
        attachment.bounds = CGRect(origin: .zero, size: size)
        return NSAttributedString(attachment: attachment)
    }

    static func displaySize(pixelWidth: Int, pixelHeight: Int, widthFraction: CGFloat) -> CGSize {
        guard pixelWidth > 0, pixelHeight > 0 else { return .zero }
        let width = min((columnWidth * widthFraction).rounded(), CGFloat(pixelWidth))
        return CGSize(width: width, height: (width * CGFloat(pixelHeight) / CGFloat(pixelWidth)).rounded())
    }

    private static func line(_ string: String, font: NSFont, color: NSColor, spacingAfter: CGFloat) -> NSAttributedString {
        NSAttributedString(string: string + "\n", attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph(spacingAfter: spacingAfter),
        ])
    }

    private static func paragraph(spacingAfter: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = spacingAfter
        return style
    }
}
