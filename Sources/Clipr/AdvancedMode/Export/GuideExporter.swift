// Sources/Clipr/AdvancedMode/Export/GuideExporter.swift
import AppKit

/// Something that went wrong with one step but didn't stop the export.
enum GuideWarning: Equatable {
    case missingImage(step: Int)
    case damagedAnnotations(step: Int)

    /// The alert text listing affected steps, or nil when there's nothing to report.
    static func summary(_ warnings: [GuideWarning]) -> String? {
        let missing = warnings.compactMap { if case .missingImage(let step) = $0 { return step } else { return nil } }
        let damaged = warnings.compactMap { if case .damagedAnnotations(let step) = $0 { return step } else { return nil } }
        var lines: [String] = []
        if !missing.isEmpty { lines.append("\(stepList(missing)): image unavailable — exported with a placeholder.") }
        if !damaged.isEmpty { lines.append("\(stepList(damaged)): annotations couldn't be read — exported without them.") }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func stepList(_ steps: [Int]) -> String {
        (steps.count == 1 ? "Step " : "Steps ") + steps.map(String.init).joined(separator: ", ")
    }
}

enum GuideExportError: LocalizedError, Equatable {
    case cancelled
    case destinationNotWritable(String)
    case writeFailed(String)
    case pdfFailed
    case clipboardFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Export cancelled."
        case .destinationNotWritable(let reason): return "Couldn't write to the chosen location. \(reason)"
        case .writeFailed(let reason): return "Couldn't finish the export. \(reason)"
        case .pdfFailed: return "Couldn't create the PDF. Try exporting as HTML instead."
        case .clipboardFailed: return "Couldn't copy the guide to the clipboard."
        }
    }
}

/// Set from the main actor when the user cancels, read by the background render loop.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// Runs one export: renders step images off the main thread (reporting progress per step and
/// stopping before the next step once cancelled), writes the output into a work folder, and only
/// then moves it to the destination — so a failed or cancelled export never leaves a half-written
/// file where the user asked for one. The work folder is always removed.
@MainActor
struct GuideExporter {
    var renderImage: @Sendable (GuideImageRef, Int) -> GuideImageRender = { GuideImages.render($0, maxPixelWidth: $1) }
    var writePDF: @MainActor (String, URL) async throws -> Void = { html, url in
        try await PDFGuideExporter().export(html: html, to: url)
    }
    var copyToClipboard: @MainActor (String) -> Bool = { GuideClipboard.write(html: $0) }
    /// Where work folders are made. Nil: the system's temporary folder on the destination's volume,
    /// so the final move is a rename.
    var workRoot: URL? = nil

    /// Returns the warnings to show. Throws `GuideExportError`. Cancelling the calling task, or
    /// `isCancelled` returning true, stops the export with `.cancelled`.
    func export(
        _ doc: GuideDocument,
        options: ExportOptions,
        to destination: URL?,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        progress: @escaping @MainActor (Double) -> Void = { _ in }
    ) async throws -> [GuideWarning] {
        let flag = CancelFlag()
        let cancelled: @Sendable () -> Bool = { flag.isSet || isCancelled() }
        return try await withTaskCancellationHandler {
            try await run(doc, options: options, destination: destination, isCancelled: cancelled, progress: progress)
        } onCancel: {
            flag.set()
        }
    }

    private func run(
        _ doc: GuideDocument, options: ExportOptions, destination: URL?,
        isCancelled: @escaping @Sendable () -> Bool, progress: @escaping @MainActor (Double) -> Void
    ) async throws -> [GuideWarning] {
        let format = options.format
        let render = renderImage
        let (images, warnings) = try await Task.detached(priority: .userInitiated) {
            try Self.renderImages(doc, format: format, render: render, isCancelled: isCancelled) { fraction in
                DispatchQueue.main.async { progress(fraction) }
            }
        }.value

        if format == .clipboard {
            // The RTF/RTFD conversion is a synchronous main-thread WebKit import that can take
            // seconds for a big guide; let the queued "images done" progress update paint first.
            await Task.yield()
            await Task.yield()
            if isCancelled() { throw GuideExportError.cancelled }
            guard copyToClipboard(HTMLGuideWriter.write(doc, images: images, mode: .embedded)) else {
                throw GuideExportError.clipboardFailed
            }
            return warnings
        }
        guard let destination else { throw GuideExportError.writeFailed("No destination was chosen.") }

        let work: URL
        do {
            work = try makeWorkFolder(for: destination)
        } catch {
            throw GuideExportError.destinationNotWritable(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: work) }

        // Markdown is assembled in a folder whose contents (guide.md, images/) are moved across.
        let output = work.appendingPathComponent(format == .markdown ? "Guide" : destination.lastPathComponent)
        if format == .pdf {
            do {
                try await writePDF(HTMLGuideWriter.write(doc, images: images, mode: .embedded), output)
            } catch {
                throw GuideExportError.pdfFailed
            }
        } else {
            let frameSeconds = options.gifFrameSeconds
            try await Task.detached(priority: .userInitiated) {
                do {
                    try Self.writeFile(doc, images: images, format: format, frameSeconds: frameSeconds, to: output)
                } catch {
                    throw GuideExportError.writeFailed(error.localizedDescription)
                }
            }.value
        }
        if isCancelled() { throw GuideExportError.cancelled }
        do {
            try Self.moveIntoPlace(output, format: format, destination: destination)
        } catch {
            throw GuideExportError.destinationNotWritable(error.localizedDescription)
        }
        return warnings
    }

    /// Each step's image at the width its format needs, plus the warnings for steps whose image is
    /// missing or whose annotations couldn't be read. GIF frames use the canvas width and skip close-ups.
    nonisolated static func renderImages(
        _ doc: GuideDocument, format: GuideFormat,
        render: (GuideImageRef, Int) -> GuideImageRender,
        isCancelled: () -> Bool, progress: (Double) -> Void
    ) throws -> (RenderedImages, [GuideWarning]) {
        var images = RenderedImages()
        var warnings: [GuideWarning] = []
        for (index, step) in doc.steps.enumerated() {
            if isCancelled() { throw GuideExportError.cancelled }
            let width = format == .gif ? GIFGuideExporter.maxCanvasWidth : GuideImages.maxPixelWidth(for: step.imageSize)
            let main = render(step.image, width)
            if let image = main.image {
                images.steps[step.number] = image
            } else {
                warnings.append(.missingImage(step: step.number))
            }
            if main.sidecarDamaged { warnings.append(.damagedAnnotations(step: step.number)) }
            if format != .gif, let zoom = step.zoom, let image = render(zoom, GuideImages.zoomPixelWidth).image {
                images.zooms[step.number] = image
            }
            progress(Double(index + 1) / Double(doc.steps.count))
        }
        if isCancelled() { throw GuideExportError.cancelled }
        return (images, warnings)
    }

    nonisolated private static func writeFile(_ doc: GuideDocument, images: RenderedImages, format: GuideFormat,
                                              frameSeconds: Double, to output: URL) throws {
        switch format {
        case .html: try Data(HTMLGuideWriter.write(doc, images: images, mode: .embedded).utf8).write(to: output)
        case .markdown: try MarkdownGuideWriter.export(doc, images: images, to: output)
        case .gif: try GIFGuideExporter.export(doc, images: images, frameSeconds: frameSeconds, to: output)
        case .pdf, .clipboard: break
        }
    }

    private func makeWorkFolder(for destination: URL) throws -> URL {
        let fileManager = FileManager.default
        guard let workRoot else {
            return try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                       appropriateFor: destination, create: true)
        }
        let folder = workRoot.appendingPathComponent("ClipprExport-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Replaces what's at the destination only now that the output is complete. For Markdown the
    /// destination is the chosen folder: `images/` moves first, so a failure never leaves a new
    /// guide.md pointing at images that aren't there.
    nonisolated static func moveIntoPlace(_ output: URL, format: GuideFormat, destination: URL) throws {
        if format == .markdown {
            for name in [MarkdownGuideWriter.imagesFolder, MarkdownGuideWriter.fileName] {
                try place(output.appendingPathComponent(name), at: destination.appendingPathComponent(name))
            }
        } else {
            try place(output, at: destination)
        }
    }

    nonisolated private static func place(_ item: URL, at target: URL) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: item)
        } else {
            try FileManager.default.moveItem(at: item, to: target)
        }
    }
}
