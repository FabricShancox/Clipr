// Sources/Clipr/AdvancedMode/Export/GuideExporter.swift
import AppKit

/// Something that went wrong with one step but didn't stop the export.
enum GuideWarning: Equatable {
    case missingImage(step: Int)
    case damagedAnnotations(step: Int)
    case missingCloseUp(step: Int)

    /// The alert text listing affected steps, or nil when there's nothing to report.
    static func summary(_ warnings: [GuideWarning]) -> String? {
        let missing = warnings.compactMap { if case .missingImage(let step) = $0 { return step } else { return nil } }
        let damaged = warnings.compactMap { if case .damagedAnnotations(let step) = $0 { return step } else { return nil } }
        let closeUps = warnings.compactMap { if case .missingCloseUp(let step) = $0 { return step } else { return nil } }
        var lines: [String] = []
        if !missing.isEmpty { lines.append("\(stepList(missing)): image unavailable — exported with a placeholder.") }
        if !damaged.isEmpty { lines.append("\(stepList(damaged)): annotations couldn't be read — exported without them.") }
        if !closeUps.isEmpty { lines.append("\(stepList(closeUps)): close-up couldn't be rendered — exported without it.") }
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

/// The new guide.md couldn't be placed and the user's old `images/` couldn't be put back either:
/// the old images stay in the hidden backup folder, which is named so the user can find it.
struct ImagesRestoreError: LocalizedError, Equatable {
    let backup: URL

    var errorDescription: String? {
        "The guide couldn't be placed, and your old images couldn't be put back. They were kept at “\(backup.path)”."
    }
}

/// Runs one export: renders step images off the main thread (reporting progress per step and
/// stopping before the next step once cancelled), writes the output into a work folder, and only
/// then moves it to the destination — so a failed or cancelled export never leaves a half-written
/// file where the user asked for one. The work folder is always removed.
@MainActor
struct GuideExporter {
    /// Prefix of the hidden work folders made beside the destination when its volume has no
    /// replacement folder (network and FAT drives).
    nonisolated static let stagingPrefix = ".Clipr-export-"

    var renderImage: @Sendable (GuideImageRef, Int) -> GuideImageRender = { GuideImages.render($0, maxPixelWidth: $1) }
    /// Cancelling the calling task cancels the print in flight (see `PDFGuideExporter.cancel()`).
    var writePDF: @MainActor (String, URL) async throws -> Void = { try await GuideExporter.printPDF($0, to: $1) }
    var copyToClipboard: @MainActor (GuideClipboard.Payload) -> Bool = { GuideClipboard.write($0) }
    /// Where work folders are made. Nil: the system's temporary folder on the destination's volume,
    /// so the final move is a rename.
    var workRoot: URL? = nil
    /// The system's replacement folder for `destination`'s volume; a seam so tests can make it fail
    /// the way it does on network and FAT drives.
    var replacementDirectory: (URL) throws -> URL = { destination in
        try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                    appropriateFor: destination, create: true)
    }

    /// Prints with a fresh `PDFGuideExporter`; cancelling the calling task cancels that exporter on
    /// the main actor, which stops the load or print at once.
    static func printPDF(_ html: String, to url: URL) async throws {
        let pdf = PDFGuideExporter()
        try await withTaskCancellationHandler {
            try await pdf.export(html: html, to: url)
        } onCancel: {
            Task { @MainActor in pdf.cancel() }
        }
    }

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
        // `images` holds every encoded picture; each branch drops it as soon as what it feeds is built.
        var (images, warnings) = try await Task.detached(priority: .userInitiated) {
            try Self.renderImages(doc, format: format, render: render, isCancelled: isCancelled) { fraction in
                DispatchQueue.main.async { progress(fraction) }
            }
        }.value

        if format == .clipboard {
            // HTML, RTF and RTFD are all built off the main thread; only the pasteboard write is here.
            let payload = try await Task.detached(priority: .userInitiated) { [images] in
                try GuideClipboard.payload(doc, images: images, isCancelled: isCancelled)
            }.value
            images = RenderedImages()
            if isCancelled() { throw GuideExportError.cancelled }
            guard copyToClipboard(payload) else { throw GuideExportError.clipboardFailed }
            return warnings
        }
        guard let destination else { throw GuideExportError.writeFailed("No destination was chosen.") }

        let work: WorkFolder
        do {
            work = try makeWorkFolder(for: destination, format: format)
        } catch {
            throw GuideExportError.destinationNotWritable(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: work.url) }

        // Markdown is assembled in a folder whose contents (guide.md, images/) are moved across.
        let output = work.url.appendingPathComponent(format == .markdown ? "Guide" : destination.lastPathComponent)
        if format == .pdf {
            let html = await Task.detached(priority: .userInitiated) { [images] in
                HTMLGuideWriter.write(doc, images: images, mode: .embedded)
            }.value
            images = RenderedImages()
            if isCancelled() { throw GuideExportError.cancelled }
            do {
                try await writePDF(html, output)
            } catch {
                if isCancelled() || (error as? PDFExportError) == .cancelled { throw GuideExportError.cancelled }
                throw GuideExportError.pdfFailed
            }
        } else {
            let frameSeconds = options.gifFrameSeconds
            try await Task.detached(priority: .userInitiated) { [images] in
                do {
                    try Self.writeFile(doc, images: images, format: format, frameSeconds: frameSeconds, to: output)
                } catch {
                    throw GuideExportError.writeFailed(error.localizedDescription)
                }
            }.value
            images = RenderedImages()
        }
        _ = images
        if isCancelled() { throw GuideExportError.cancelled }
        do {
            if work.onDestinationVolume {
                try Self.moveIntoPlace(output, format: format, destination: destination)
            } else {
                try Self.copyAcrossAndPlace(output, format: format, destination: destination)
            }
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
            if format != .gif, let zoom = step.zoom {
                if let image = render(zoom, GuideImages.zoomPixelWidth).image {
                    images.zooms[step.number] = image
                } else {
                    warnings.append(.missingCloseUp(step: step.number))
                }
            }
            progress(Double(index + 1) / Double(doc.steps.count))
        }
        if isCancelled() { throw GuideExportError.cancelled }
        return (images, warnings)
    }

    nonisolated private static func writeFile(_ doc: GuideDocument, images: RenderedImages, format: GuideFormat,
                                              frameSeconds: Double, to output: URL) throws {
        switch format {
        case .html: try writeUTF8(HTMLGuideWriter.write(doc, images: images, mode: .embedded), to: output)
        case .markdown: try MarkdownGuideWriter.export(doc, images: images, to: output)
        case .gif: try GIFGuideExporter.export(doc, images: images, frameSeconds: frameSeconds, to: output)
        case .pdf, .clipboard: break
        }
    }

    /// Writes the string's own UTF-8 bytes, so a large guide isn't held twice (String and Data).
    nonisolated static func writeUTF8(_ text: String, to url: URL) throws {
        var text = text
        try text.withUTF8 { buffer in
            guard let base = buffer.baseAddress else { return try Data().write(to: url) }
            try Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: buffer.count, deallocator: .none).write(to: url)
        }
    }

    /// A folder to assemble the output in, and whether moving out of it is a same-volume rename.
    struct WorkFolder {
        let url: URL
        let onDestinationVolume: Bool
    }

    /// The system's replacement folder on the destination's volume; failing that (network and FAT
    /// drives), a hidden folder beside the destination — for Markdown, inside the chosen folder, which
    /// may itself be a volume's root; and only if that can't be made either, the system temp folder,
    /// from which `copyAcrossAndPlace` copies the output over before renaming it into place.
    private func makeWorkFolder(for destination: URL, format: GuideFormat) throws -> WorkFolder {
        let fileManager = FileManager.default
        if let workRoot {
            let folder = workRoot.appendingPathComponent("ClipprExport-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            return WorkFolder(url: folder, onDestinationVolume: true)
        }
        if let folder = try? replacementDirectory(destination) {
            return WorkFolder(url: folder, onDestinationVolume: true)
        }
        let parent = format == .markdown ? destination : destination.deletingLastPathComponent()
        let sibling = parent.appendingPathComponent(Self.stagingPrefix + UUID().uuidString, isDirectory: true)
        if (try? fileManager.createDirectory(at: sibling, withIntermediateDirectories: false)) != nil {
            return WorkFolder(url: sibling, onDestinationVolume: true)
        }
        let folder = fileManager.temporaryDirectory.appendingPathComponent("ClipprExport-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return WorkFolder(url: folder, onDestinationVolume: false)
    }

    /// For output built on another volume: copies it to a hidden item beside the destination first,
    /// then renames that into place, so the destination's own name never holds a half-copied file.
    /// The hidden copy is always removed.
    nonisolated static func copyAcrossAndPlace(_ output: URL, format: GuideFormat, destination: URL) throws {
        let parent = format == .markdown ? destination : destination.deletingLastPathComponent()
        let staged = parent.appendingPathComponent(stagingPrefix + UUID().uuidString + (format == .markdown ? "" : "-" + destination.lastPathComponent))
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: output, to: staged)
        try moveIntoPlace(staged, format: format, destination: destination)
    }

    /// Replaces what's at the destination only now that the output is complete. For Markdown the
    /// destination is the chosen folder: the old `images/` is set aside while the new one moves in,
    /// and put back if guide.md then can't be placed, so a failed export leaves the folder as it was
    /// (an old guide.md never ends up beside new images, nor a new one beside missing images). If the
    /// old images can't be put back, they are left in the backup and the error says where.
    nonisolated static func moveIntoPlace(_ output: URL, format: GuideFormat, destination: URL,
                                          placeGuide: (URL, URL) throws -> Void = { try place($0, at: $1) },
                                          restoreImages: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) throws {
        guard format == .markdown else { return try place(output, at: destination) }
        let fileManager = FileManager.default
        let imagesTarget = destination.appendingPathComponent(MarkdownGuideWriter.imagesFolder)
        let backup = destination.appendingPathComponent(".images-backup-\(UUID().uuidString)")
        let hadImages = fileManager.fileExists(atPath: imagesTarget.path)
        if hadImages { try fileManager.moveItem(at: imagesTarget, to: backup) }
        func restore() throws {
            guard hadImages else { return }
            do {
                try restoreImages(backup, imagesTarget)
            } catch {
                throw ImagesRestoreError(backup: backup)
            }
        }
        do {
            try fileManager.moveItem(at: output.appendingPathComponent(MarkdownGuideWriter.imagesFolder), to: imagesTarget)
        } catch {
            try restore()
            throw error
        }
        do {
            try placeGuide(output.appendingPathComponent(MarkdownGuideWriter.fileName),
                           destination.appendingPathComponent(MarkdownGuideWriter.fileName))
        } catch {
            try? fileManager.removeItem(at: imagesTarget)
            try restore()
            throw error
        }
        if hadImages { try? fileManager.removeItem(at: backup) }
    }

    nonisolated private static func place(_ item: URL, at target: URL) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: item)
        } else {
            try FileManager.default.moveItem(at: item, to: target)
        }
    }
}
