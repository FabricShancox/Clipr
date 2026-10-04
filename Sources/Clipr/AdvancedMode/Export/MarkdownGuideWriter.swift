// Sources/Clipr/AdvancedMode/Export/MarkdownGuideWriter.swift
import Foundation

/// A Markdown guide for GitHub, MkDocs, wikis and Notion import: `guide.md` plus an `images/`
/// folder it links to relatively, so the folder can be moved or committed as it is.
enum MarkdownGuideWriter {
    static let fileName = "guide.md"
    static let imagesFolder = "images"

    static func write(_ doc: GuideDocument, images: RenderedImages) -> String {
        var lines = ["# \(CaptionMarkup.escapeMarkdown(doc.title))", "_\(doc.subtitle)_", ""]
        for step in doc.steps {
            let number = step.number
            lines.append("## \(number). \(CaptionMarkup.markdown(step.caption, fallbackNumber: number))")
            lines.append(imageLine(images.steps[number], step: number, zoom: false, alt: "Step \(number)", size: step.imageSize))
            if step.zoom != nil {
                lines.append("")
                lines.append(imageLine(images.zooms[number], step: number, zoom: true, alt: "Step \(number) close-up", size: .full))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Writes `guide.md` and `images/` into `folder`, creating it if needed.
    static func export(_ doc: GuideDocument, images: RenderedImages, to folder: URL) throws {
        let imagesURL = folder.appendingPathComponent(imagesFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        for step in doc.steps {
            if let image = images.steps[step.number] {
                try image.data.write(to: imagesURL.appendingPathComponent(GuideImage.fileName(step: step.number, zoom: false, kind: image.kind)))
            }
            if step.zoom != nil, let zoom = images.zooms[step.number] {
                try zoom.data.write(to: imagesURL.appendingPathComponent(GuideImage.fileName(step: step.number, zoom: true, kind: zoom.kind)))
            }
        }
        try Data(write(doc, images: images).utf8).write(to: folder.appendingPathComponent(fileName))
    }

    /// Whether exporting into `folder` would overwrite an earlier guide, so the user is asked first.
    static func hasExistingGuide(in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName).path)
    }

    /// Markdown image syntax has no width, so sized steps use an `<img>` tag, which GitHub, MkDocs
    /// and most wikis render; Full steps keep plain Markdown.
    private static func imageLine(_ image: GuideImage?, step: Int, zoom: Bool, alt: String, size: ImageSize) -> String {
        guard let image else { return "_Image unavailable_" }
        let path = "\(imagesFolder)/\(GuideImage.fileName(step: step, zoom: zoom, kind: image.kind))"
        if size == .full { return "![\(alt)](\(path))" }
        return "<img src=\"\(path)\" alt=\"\(alt)\" width=\"\(size.widthPercent)%\">"
    }
}
