import AppKit

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
    /// The third argument is the guide's step count, which sets how long printing may take.
    var writePDF: @MainActor (String, URL, Int) async throws -> Void = {
        try await GuideExporter.printPDF($0, to: $1, timeout: PDFGuideExporter.timeout(forSteps: $2))
    }
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
    static func printPDF(_ html: String, to url: URL, timeout: TimeInterval = PDFGuideExporter.defaultTimeout) async throws {
        let pdf = PDFGuideExporter(timeout: timeout)
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
            try await copyGuide(doc, images: &images, isCancelled: isCancelled)
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
        try await writeOutput(doc, images: &images, options: options, to: output, isCancelled: isCancelled)
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

    /// HTML, RTF and RTFD are all built off the main thread; only the pasteboard write is here.
    /// `images` is emptied as soon as the payload is built.
    private func copyGuide(_ doc: GuideDocument, images: inout RenderedImages,
                           isCancelled: @escaping @Sendable () -> Bool) async throws {
        let payload = try await Task.detached(priority: .userInitiated) { [images] in
            try GuideClipboard.payload(doc, images: images, isCancelled: isCancelled)
        }.value
        images = RenderedImages()
        if isCancelled() { throw GuideExportError.cancelled }
        guard copyToClipboard(payload) else { throw GuideExportError.clipboardFailed }
    }

    /// Writes the PDF, HTML, Markdown or GIF to `output` in the work folder. `images` is emptied as
    /// soon as what it feeds is built.
    private func writeOutput(_ doc: GuideDocument, images: inout RenderedImages, options: ExportOptions,
                             to output: URL, isCancelled: @escaping @Sendable () -> Bool) async throws {
        let format = options.format
        if format == .pdf {
            let html = await Task.detached(priority: .userInitiated) { [images] in
                HTMLGuideWriter.write(doc, images: images, mode: .embedded)
            }.value
            images = RenderedImages()
            if isCancelled() { throw GuideExportError.cancelled }
            do {
                try await writePDF(html, output, doc.steps.count)
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
            } else if main.sidecarDamaged {
                warnings.append(.damagedAnnotations(step: step.number))
            } else {
                warnings.append(.missingImage(step: step.number))
            }
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
}
