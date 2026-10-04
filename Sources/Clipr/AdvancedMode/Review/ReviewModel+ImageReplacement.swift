import AppKit

/// Replacing a step's image (retake or file), and swapping it back on undo / redo.
extension ReviewModel {
    /// For failures found outside the model, such as a chosen replacement file that won't open.
    func showBanner(_ text: String) { banner = text }

    static let editorOpenBanner = "Close the image editor for this step first"
    static let stepRemovedBanner = "Couldn't replace the image — that step was removed"

    /// Swaps a step's image for a retake. See `replaceImage(for:withPNG:)`.
    func replaceImage(for id: UUID, with image: NSImage) {
        guard !isReadOnly else { return }
        guard let step = manifest.steps.first(where: { $0.id == id }) else { banner = Self.stepRemovedBanner; return }
        guard let data = ImageEncoding.png(image) else {
            banner = "Couldn't replace the image for \(step.file)"
            return
        }
        replaceImage(for: id, withPNG: data)
    }

    /// Swaps a step's image for new PNG data. The old image and everything derived from it
    /// (annotations, zoom crop, edited preview) go to the Trash, and the click point and zoom are
    /// cleared because they describe the old image. The step keeps its filename, place and caption.
    ///
    /// The new image is written to a temporary file before anything is trashed, so a failed encode
    /// or write never touches the old image; and the old files are trashed all-or-nothing, so no
    /// stale companion is left to shadow the new image.
    func replaceImage(for id: UUID, withPNG data: Data) {
        guard !isReadOnly else { return }
        // A retake or a Replace-with-File decode can finish after the step was deleted; the
        // user chose an image, so say why nothing happened.
        guard let step = manifest.steps.first(where: { $0.id == id }) else { banner = Self.stepRemovedBanner; return }
        guard !stepsInEditor.contains(id) else { banner = Self.editorOpenBanner; return }
        flushPendingCaption()
        let failure = "Couldn't replace the image for \(step.file)"
        let stepURL = url(for: step)
        // Hidden, and without the "Step_" prefix, so a leftover after a crash is never taken for
        // a step when a session is rebuilt from its PNGs.
        let temp = folder.appendingPathComponent(".\((step.file as NSString).deletingPathExtension).replacing.png")
        do { try writeImage(data, temp) } catch {
            try? FileManager.default.removeItem(at: temp)
            banner = failure
            return
        }
        // Owner-only like every step the recorder writes; the move below keeps it.
        SessionFolder.restrict(temp)
        let old: TrashedStep
        do { old = try files.trashAll(step.file, in: folder) } catch {
            try? FileManager.default.removeItem(at: temp)
            banner = failure
            return
        }
        do { try files.moveItem(temp, stepURL) } catch {
            try? FileManager.default.removeItem(at: temp)
            do { try files.restore(old) } catch {
                banner = Self.lostImageBanner(step.file, trashed: old)
                return
            }
            banner = failure
            return
        }
        applyImageFields(clickPoint: nil, zoomFile: nil, for: id)
        registerUndo(Self.replaceImageAction, imageSwapOf: id) { $0.swapImage(for: id, restoring: old, record: step) }
    }

    static let replaceImageAction = "Replace Image"

    /// When putting an image back fails too, the step is left without one; the banner says where
    /// the image went so the user can recover it by hand.
    private static func lostImageBanner(_ file: String, trashed: TrashedStep) -> String {
        let location = trashed.moves.first?.trashed.path ?? "the Trash"
        return "Couldn't put back the image for \(file) — it's in the Trash at \(location)"
    }

    /// Undo and redo of a replacement: the current image set goes to the Trash and `trashed` comes
    /// back, with the click data that belongs to it. Each swap registers the opposite swap.
    private func swapImage(for id: UUID, restoring trashed: TrashedStep, record: StepRecord) {
        // undo()/redo() are the only supported entry points: they refuse while the step's editor is
        // open, and the editor would write its old image back over this swap.
        assert(!stepsInEditor.contains(id), "swapImage must be reached through undo()/redo(), which refuse while the step's editor is open")
        guard let current = manifest.steps.first(where: { $0.id == id }) else {
            banner = "Couldn't \(undoManager.isRedoing ? "redo" : "undo") — \(record.file) is no longer in this session"
            return
        }
        // Checked before anything moves: finding out mid-swap would mean trashing the current
        // image with nothing to put in its place.
        guard StepFiles.isInTrash(trashed) else {
            banner = "Couldn't restore \(trashed.file) — it's no longer in the Trash"
            return
        }
        let currentFiles: TrashedStep
        do { currentFiles = try files.trashAll(current.file, in: folder) } catch {
            banner = "Couldn't replace the image for \(current.file)"
            return
        }
        do {
            try files.restore(trashed)
        } catch {
            do { try files.restore(currentFiles) } catch {
                banner = Self.lostImageBanner(current.file, trashed: currentFiles)
                return
            }
            banner = "Couldn't restore \(trashed.file)"
            return
        }
        applyImageFields(clickPoint: record.clickPoint, zoomFile: record.zoomFile, for: id)
        registerUndo(Self.replaceImageAction, imageSwapOf: id) { $0.swapImage(for: id, restoring: currentFiles, record: current) }
    }

    private func applyImageFields(clickPoint: CGPoint?, zoomFile: String?, for id: UUID) {
        // Callers check the step exists before moving any files, so this is a last line of defence.
        guard let index = manifest.steps.firstIndex(where: { $0.id == id }) else {
            banner = "Couldn't update the step — it's no longer in this session"
            return
        }
        manifest.steps[index].clickPoint = clickPoint
        manifest.steps[index].zoomFile = zoomFile
        _ = persist()
        for url in StepFiles.companions(of: manifest.steps[index].file, in: folder) + [url(for: manifest.steps[index])] {
            thumbnails.remove(url)
        }
        thumbnails.remove(folder.appendingPathComponent(FilenameGenerator.editedName(fromRaw: manifest.steps[index].file)))
        thumbnailURLs[manifest.steps[index].file] = nil
        imageVersions[id, default: 0] += 1
    }
}
