import Cocoa

final class StorageManager {
    /// Mutable so a save-folder change made in Preferences takes effect immediately, without
    /// needing to rebuild the manager (which every capture path already holds a reference to) or
    /// relaunch the app. `AppDelegate` reassigns this from its `PreferencesWindowController`'s
    /// `onSaveFolderChanged` callback; every path below reads it at call time.
    var baseFolder: URL

    init(baseFolder: URL) {
        self.baseFolder = baseFolder
    }

    func saveRawCapture(_ image: NSImage, date: Date) throws -> URL {
        let name = FilenameGenerator.rawScreenshotName(date: date)
        return try write(image, to: baseFolder.appendingPathComponent(name))
    }

    /// Auto-save (see `EditorView.scheduleAutoSave`) calls this repeatedly for the same
    /// `rawURL` as editing continues — every debounced edit should overwrite the same
    /// `_edited.png`, not spawn a fresh `_edited_1.png`, `_edited_2.png`, ... file each time. The
    /// collision-avoiding `write(_:to:)` path is for genuinely distinct captures (raw screenshots,
    /// tutorial steps) that happen to land on the same generated filename; a repeat write to the
    /// exact same edited-capture path is instead the SAME edit being saved again, so it overwrites.
    func saveEditedCapture(_ image: NSImage, rawURL: URL) throws -> URL {
        let editedName = FilenameGenerator.editedName(fromRaw: rawURL.lastPathComponent)
        let editedURL = rawURL.deletingLastPathComponent().appendingPathComponent(editedName)
        return try write(image, to: editedURL, overwrite: true)
    }

    /// Replaces the raw capture's own pixels — used by crop and canvas-resize, which change the
    /// base image itself rather than adding an annotation on top of it.
    ///
    /// Without this the crop lived only in memory: `_edited.png` and the sidecar were written with
    /// the new geometry while `rawURL` kept the original pixels, so reopening the capture loaded
    /// the uncropped image and positioned annotations that had been remapped for the cropped one
    /// — the crop silently undone and every annotation misplaced.
    func overwriteRawCapture(_ image: NSImage, rawURL: URL) throws {
        _ = try write(image, to: rawURL, overwrite: true)
    }

    /// Persists the live, editable annotation objects for a capture as a JSON sidecar, so
    /// reopening it from Recents (or relaunching Clipr entirely) restores actual editable
    /// annotations rather than only a flattened preview image. Called alongside
    /// `saveEditedCapture` on every auto-save.
    func saveAnnotations(_ annotations: [AnnotationObject], rawURL: URL) throws {
        let url = annotationsURL(forRaw: rawURL)
        let data = try JSONEncoder().encode(annotations)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Outcome of reading a capture's annotation sidecar. `missing` and `corrupt` are deliberately
    /// distinct: collapsing both to "no annotations" meant an unreadable sidecar looked like a
    /// never-edited capture, and the next auto-save then overwrote it — destroying the user's
    /// annotations permanently, with nothing shown to them.
    enum AnnotationsLoad {
        /// No sidecar yet — a fresh, never-edited capture.
        case missing
        case loaded([AnnotationObject])
        /// The sidecar exists but could not be decoded. The caller must not let it be overwritten.
        case corrupt(Error)
    }

    func readAnnotations(rawURL: URL) -> AnnotationsLoad {
        let url = annotationsURL(forRaw: rawURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            return .loaded(try JSONDecoder().decode([AnnotationObject].self, from: Data(contentsOf: url)))
        } catch {
            return .corrupt(error)
        }
    }

    /// Moves an unreadable sidecar aside, returning where it went.
    ///
    /// Called before the editor opens a capture whose sidecar won't decode, so the next auto-save
    /// writes a fresh file instead of overwriting one whose contents might still be recoverable by
    /// hand. Never deletes anything.
    @discardableResult
    func quarantineAnnotations(rawURL: URL) -> URL? {
        let url = annotationsURL(forRaw: rawURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let backup = uniqueURL(for: url.appendingPathExtension("bak"))
        do {
            try FileManager.default.moveItem(at: url, to: backup)
            return backup
        } catch {
            NSLog("Clipr: could not set aside unreadable annotations for \(rawURL.lastPathComponent): \(error)")
            return nil
        }
    }

    /// Convenience for callers that only care about the annotations themselves; treats a missing
    /// and an unreadable sidecar alike. Prefer `readAnnotations` where the difference matters.
    func loadAnnotations(rawURL: URL) -> [AnnotationObject] {
        if case .loaded(let annotations) = readAnnotations(rawURL: rawURL) { return annotations }
        return []
    }

    /// Removes a capture's annotation sidecar, if any — called alongside deleting the raw and
    /// `_edited` files so no orphaned sidecar is left behind.
    func deleteAnnotations(rawURL: URL) {
        try? FileManager.default.removeItem(at: annotationsURL(forRaw: rawURL))
    }

    /// Deletes a capture entirely: its raw file, `_edited` preview, and annotations sidecar, if
    /// any of those exist. Used when the user deletes a Recent capture from the editor sidebar.
    func deleteCapture(rawURL: URL) {
        try? FileManager.default.removeItem(at: rawURL)
        let editedURL = rawURL.deletingLastPathComponent()
            .appendingPathComponent(FilenameGenerator.editedName(fromRaw: rawURL.lastPathComponent))
        try? FileManager.default.removeItem(at: editedURL)
        deleteAnnotations(rawURL: rawURL)
    }

    /// Renames a capture and the two files keyed off its name — the flattened `_edited.png` and
    /// the annotations sidecar — returning the raw file's new URL.
    ///
    /// A rename must never destroy someone else's capture, so rather than moving each file and
    /// hoping, this first picks a base name where all three destinations are free (suffixing
    /// `_1`, `_2`, ... as `write` does for colliding captures) and only then moves. That means no
    /// `moveItem` here can collide, and nothing is ever deleted to make room. The companions are
    /// moved only if they exist, since a never-edited capture legitimately has neither.
    func renameCapture(rawURL: URL, toBaseName baseName: String) throws -> URL {
        guard let requested = FilenameGenerator.sanitizedBaseName(baseName) else {
            throw StorageError.invalidFilename(baseName)
        }
        let folder = rawURL.deletingLastPathComponent()
        let ext = rawURL.pathExtension.isEmpty ? "png" : rawURL.pathExtension
        let currentBase = rawURL.deletingPathExtension().lastPathComponent
        guard requested != currentBase else { return rawURL }

        let resolved = availableBaseName(requested, ext: ext, in: folder, ignoring: rawURL)
        let target = folder.appendingPathComponent("\(resolved).\(ext)")
        try FileManager.default.moveItem(at: rawURL, to: target)

        move(
            folder.appendingPathComponent(FilenameGenerator.editedName(fromRaw: rawURL.lastPathComponent)),
            to: folder.appendingPathComponent(FilenameGenerator.editedName(fromRaw: target.lastPathComponent))
        )
        move(annotationsURL(forRaw: rawURL), to: annotationsURL(forRaw: target))
        return target
    }

    /// Best-effort move used for a rename's companion files: they may simply not exist, and
    /// failing to move a sidecar should not strand the raw file under a half-applied rename.
    private func move(_ from: URL, to: URL) {
        guard FileManager.default.fileExists(atPath: from.path) else { return }
        do {
            try FileManager.default.moveItem(at: from, to: to)
        } catch {
            NSLog("Clipr: rename could not move \(from.lastPathComponent): \(error)")
        }
    }

    /// First base name whose raw, `_edited` and sidecar paths are all free. The capture's own
    /// current files are ignored, so a case-only rename ("shot" -> "Shot") isn't mistaken for a
    /// clash with itself on a case-insensitive volume.
    private func availableBaseName(_ base: String, ext: String, in folder: URL, ignoring rawURL: URL) -> String {
        let own = Set([
            rawURL.lastPathComponent,
            FilenameGenerator.editedName(fromRaw: rawURL.lastPathComponent),
            FilenameGenerator.annotationsName(fromRaw: rawURL.lastPathComponent)
        ].map { $0.lowercased() })

        func taken(_ candidate: String) -> Bool {
            let raw = "\(candidate).\(ext)"
            let names = [raw, FilenameGenerator.editedName(fromRaw: raw), FilenameGenerator.annotationsName(fromRaw: raw)]
            return names.contains { name in
                !own.contains(name.lowercased())
                    && FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
            }
        }

        guard taken(base) else { return base }
        var suffix = 1
        while taken("\(base)_\(suffix)") { suffix += 1 }
        return "\(base)_\(suffix)"
    }

    private func annotationsURL(forRaw rawURL: URL) -> URL {
        rawURL.deletingLastPathComponent().appendingPathComponent(FilenameGenerator.annotationsName(fromRaw: rawURL.lastPathComponent))
    }

    func createSessionFolder(date: Date) throws -> URL {
        let folder = baseFolder.appendingPathComponent(FilenameGenerator.sessionFolderName(date: date))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw StorageError.folderCreationFailed(folder)
        }
        return folder
    }

    func saveStep(_ image: NSImage, index: Int, in sessionFolder: URL) throws -> URL {
        let name = FilenameGenerator.stepName(index: index)
        return try write(image, to: sessionFolder.appendingPathComponent(name))
    }

    func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    /// Writes `image` to a user-chosen location in `format` — the "Save As…" path, as opposed to
    /// the app's own PNG-only capture storage.
    func export(_ image: NSImage, to url: URL, format: ExportFormat) throws {
        // JPEG can't carry alpha: a capture whose canvas was resized outward has transparent
        // regions that would encode as black, so flatten onto white first.
        let source = format.needsOpaqueBackground ? Self.onWhite(image) : image
        guard let tiff = source.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: format.bitmapType, properties: format.properties) else {
            throw StorageError.pngEncodingFailed
        }
        try data.write(to: url, options: .atomic)
    }

    private static func onWhite(_ image: NSImage) -> NSImage {
        let size = image.size
        let result = NSImage(size: size)
        result.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(origin: .zero, size: size))
        result.unlockFocus()
        return result
    }

    private func write(_ image: NSImage, to url: URL, overwrite: Bool = false) throws -> URL {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw StorageError.pngEncodingFailed
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // `overwrite` writes to `url` exactly as given (replacing whatever's already there);
        // otherwise resolve a collision by appending a numeric suffix, for callers where a
        // clash means two genuinely different captures landed on the same generated name.
        let finalURL = overwrite ? url : uniqueURL(for: url)
        if overwrite, FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try pngData.write(to: finalURL)
        return finalURL
    }

    private func uniqueURL(for url: URL) -> URL {
        // If the file doesn't exist, use the URL as-is
        guard FileManager.default.fileExists(atPath: url.path) else {
            return url
        }

        // File exists; append numeric suffix before extension
        let pathWithoutExtension = url.deletingPathExtension().path
        let ext = url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)"
        var suffix = 1

        while true {
            let candidatePath = "\(pathWithoutExtension)_\(suffix)\(ext)"
            let candidateURL = URL(fileURLWithPath: candidatePath)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            suffix += 1
        }
    }
}
