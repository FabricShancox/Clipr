// Sources/Clipr/AdvancedMode/Export/GuideDocument.swift
import Foundation
import CoreGraphics

/// The five ways a reviewed session leaves Clipr. Not called `ExportFormat`: that name is the
/// image editor's PNG/JPEG "Save As…" choice.
enum GuideFormat: String, CaseIterable, Identifiable {
    case pdf, html, markdown, gif, clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return "PDF"
        case .html: return "HTML"
        case .markdown: return "Markdown"
        case .gif: return "GIF"
        case .clipboard: return "Copy as Rich Text"
        }
    }

    /// The extension of the single file this format writes; nil for Markdown (a folder) and the
    /// clipboard (no file).
    var fileExtension: String? {
        switch self {
        case .pdf: return "pdf"
        case .html: return "html"
        case .gif: return "gif"
        case .markdown, .clipboard: return nil
        }
    }

    /// The save panel's starting name: the title made safe for a filename, "Guide" when nothing
    /// usable is left of it.
    func suggestedFileName(for title: String) -> String {
        let base = FilenameGenerator.sanitizedBaseName(CaptionMarkup.stripBidi(title)) ?? "Guide"
        return fileExtension.map { "\(base).\($0)" } ?? base
    }
}

/// What the export sheet chose. The title is per session; the rest is remembered by `SettingsStore`.
struct ExportOptions: Equatable {
    static let gifFrameRange: ClosedRange<Double> = 1...5

    var format: GuideFormat = .pdf
    var title: String
    var includeZoom = false
    var gifFrameSeconds: Double = 2
}

extension ImageSize {
    /// The step image's width as a whole percentage of the guide's content width.
    var widthPercent: Int { Int((widthFraction * 100).rounded()) }
}

/// Where a step's picture comes from. Rendering (annotations, downsampling, encoding) is left to
/// `GuideImages`, so building a document stays cheap and pure.
enum GuideImageRef: Equatable {
    /// A raw step PNG; its annotation sidecar sits next to it under the usual name.
    case file(URL)
    /// A close-up, cut from the step's annotated image at export time — never the `_zoom.png`
    /// saved at capture, which holds raw pixels that redactions and crops made since don't reach.
    case closeUp(CloseUpSource)
    case missing
}

/// What a close-up is rebuilt from. `capturedZoom` is only a reference: it proves the click point
/// still lands on the same pixels it did at capture, and is never exported itself.
struct CloseUpSource: Equatable {
    /// The raw step PNG; its annotation sidecar sits next to it under the usual name.
    let step: URL
    /// The `_zoom.png` written at capture.
    let capturedZoom: URL
    /// Image points, top-left origin, as recorded at capture.
    let clickPoint: CGPoint
}

/// One encoded image ready to embed or write out.
struct GuideImage: Equatable {
    enum Kind: Equatable { case png, jpeg }

    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let kind: Kind

    var mimeType: String { kind == .png ? "image/png" : "image/jpeg" }

    /// Positional names ("step-01.png", "step-01-zoom.jpg"), so an export never depends on how the
    /// session's own files happen to be named.
    static func fileName(step: Int, zoom: Bool, kind: Kind) -> String {
        String(format: "step-%02d", step) + (zoom ? "-zoom" : "") + (kind == .png ? ".png" : ".jpg")
    }
}

/// Rendered images keyed by step number. Close-ups get their own map because a step can have both.
struct RenderedImages: Equatable {
    var steps: [Int: GuideImage] = [:]
    var zooms: [Int: GuideImage] = [:]
}

struct GuideStep: Equatable {
    /// 1-based position in the exported guide, not in the session.
    let number: Int
    /// Inline Markdown, untrusted; nil when the step has no caption.
    let caption: String?
    let appName: String?
    let imageSize: ImageSize
    let image: GuideImageRef
    /// Nil unless close-ups were asked for and this step had one captured (still on disk).
    let zoom: GuideImageRef?
}

/// A reviewed session reduced to what every export format needs.
struct GuideDocument: Equatable {
    let title: String
    let date: Date
    let steps: [GuideStep]

    /// The selected steps if any are still in the session, otherwise all of them, in Review order
    /// and numbered from 1. A selection that names only steps no longer in the manifest (deleted
    /// since) falls back to every step rather than exporting an empty guide.
    static func make(manifest: SessionManifest, folder: URL, selection: Set<UUID>, options: ExportOptions) -> GuideDocument {
        let live = selection.intersection(manifest.steps.map(\.id))
        let chosen = live.isEmpty ? manifest.steps : manifest.steps.filter { live.contains($0.id) }
        let steps = chosen.enumerated().map { index, record in
            GuideStep(
                number: index + 1,
                caption: nonBlank(record.caption),
                appName: nonBlank(record.appName),
                imageSize: record.imageSize ?? .full,
                image: ref(folder.appendingPathComponent(record.file)),
                zoom: options.includeZoom ? closeUpRef(record, folder: folder) : nil
            )
        }
        let title = nonBlank(options.title.split(whereSeparator: \.isNewline).joined(separator: " ")) ?? folder.lastPathComponent
        return GuideDocument(title: title, date: manifest.createdAt, steps: steps)
    }

    /// "4 Oct 2026 · 7 steps".
    var subtitle: String {
        "\(Self.dateText(date)) · \(steps.count == 1 ? "1 step" : "\(steps.count) steps")"
    }

    /// Always English day-month-year, matching the rest of Clipr's English-only copy.
    static func dateText(_ date: Date, timeZone: TimeZone = .current) -> String {
        DateFormats.string(date, pattern: "d MMM yyyy", timeZone: timeZone)
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func ref(_ url: URL) -> GuideImageRef {
        FileManager.default.fileExists(atPath: url.path) ? .file(url) : .missing
    }

    /// A close-up whose capture-time file is gone is simply left out: it's an extra, not the step
    /// itself. The file name is derived from the step's, never taken from `zoomFile`, so a crafted
    /// session.json can't point the export at a file outside the session.
    private static func closeUpRef(_ record: StepRecord, folder: URL) -> GuideImageRef? {
        guard record.zoomFile != nil, let clickPoint = record.clickPoint else { return nil }
        let zoom = folder.appendingPathComponent(FilenameGenerator.zoomName(fromStep: record.file))
        guard FileManager.default.fileExists(atPath: zoom.path) else { return nil }
        return .closeUp(CloseUpSource(step: folder.appendingPathComponent(record.file), capturedZoom: zoom, clickPoint: clickPoint))
    }
}
