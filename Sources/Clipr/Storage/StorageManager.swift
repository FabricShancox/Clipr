import Cocoa

final class StorageManager {
    /// Mutable so a save-folder change made in Preferences takes effect immediately, without
    /// needing to rebuild the manager (which every capture path already holds a reference to) or
    /// relaunch the app. `AppDelegate` reassigns this from the `PreferencesWindowController`'s
    /// `onSaveFolderChanged` callback; every path below reads it at call time.
    var baseFolder: URL

    /// Writes encoded image data to disk. `.atomic` writes a temporary file beside the target and
    /// renames it over the old one, so an overwrite either fully lands or leaves the previous file
    /// intact — there is never a moment with no file. A seam so tests can inject a failed write.
    var writeData: (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }

    init(baseFolder: URL) {
        self.baseFolder = baseFolder
    }

    /// Captures can hold anything that was on screen, and session captions can hold typed text,
    /// so what Clipr writes into its own folders is readable by the owner only. Under `~/Pictures`
    /// that changes nothing (the home folder is already private), but a save folder in
    /// `/Users/Shared`, on an external disk or in a synced folder otherwise left every screenshot
    /// readable by other accounts. Save As… exports keep the default permissions — handing a copy
    /// to someone is their point.
    static let privateFilePermissions = 0o600
    static let privateFolderPermissions = 0o700

    /// Creates `folder` (and any missing parents) owner-only. An existing folder is left as is.
    static func createPrivateFolder(_ folder: URL) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: privateFolderPermissions]
        )
    }

    /// Makes a file Clipr just wrote owner-only. Best effort: a volume without POSIX permissions
    /// (FAT, some network shares) can't do it, and that mustn't fail the save.
    static func restrictToOwner(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: privateFilePermissions], ofItemAtPath: url.path)
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
    ///
    /// Capture storage is PNG-only, so this refuses anything that isn't a `.png`: writing PNG
    /// bytes under a `.jpg`/`.heic` name would leave a mislabelled file and destroy the original
    /// encoding. Files from outside Clipr reach the editor through `importForEditing`, so this is
    /// a backstop, not the normal path.
    func overwriteRawCapture(_ image: NSImage, rawURL: URL) throws {
        guard rawURL.pathExtension.lowercased() == "png" else {
            throw StorageError.notAPNGCapture(rawURL)
        }
        _ = try write(image, to: rawURL, overwrite: true)
    }

    /// The file the editor should work on for an image picked with "Open Image…".
    ///
    /// The editor writes to its "raw" file (crop and canvas-resize replace its pixels; auto-save
    /// puts `_edited.png` and the sidecar beside it), so editing a user's own file in place would
    /// overwrite their original — and give a JPEG/HEIC PNG bytes under its old extension. Only a
    /// PNG sitting directly in the capture folder is edited in place; anything else is imported
    /// as a new PNG there (named after the original, suffixed if taken) and the original is left
    /// exactly as it was.
    func importForEditing(_ url: URL, image: NSImage) throws -> URL {
        let folder = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        let base = baseFolder.resolvingSymlinksInPath().standardizedFileURL
        if folder.path == base.path, url.pathExtension.lowercased() == "png" {
            return url
        }
        let name = Self.importedBaseName(FilenameGenerator.sanitizedBaseName(url.deletingPathExtension().lastPathComponent) ?? "Image")
        let target = baseFolder.appendingPathComponent("\(name).png")
        if url.pathExtension.lowercased() == "png" {
            // Byte-for-byte, so the copy keeps the original's metadata and colour profile. Written as
            // data rather than copied, so extended attributes (com.apple.quarantine, Finder tags,
            // where-from URLs) don't come along.
            try Self.createPrivateFolder(baseFolder)
            let destination = uniqueURL(for: target)
            try Data(contentsOf: url).write(to: destination, options: .atomic)
            Self.restrictToOwner(destination)
            return destination
        }
        return try write(image, to: target)
    }

    /// An imported file named like one of a capture's companions (`X_edited`, `X_zoom`,
    /// `X_annotations`) would be picked up as that capture's edited image, close-up or sidecar, so
    /// it gets a suffix.
    static func importedBaseName(_ name: String) -> String {
        let lower = name.lowercased()
        return ["_edited", "_zoom", "_annotations"].contains { lower.hasSuffix($0) } ? name + "-imported" : name
    }

    /// Moves a file to the Trash. A seam so tests don't fill the real Trash.
    var trashItem: (URL) throws -> Void = { url in
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// Moves a capture to the Trash: its raw file, then its `_edited` preview and annotations
    /// sidecar, if they exist. Used when the user deletes a Recent capture from the editor
    /// sidebar.
    ///
    /// Trash rather than `removeItem`, so a mis-click on the small delete button can be recovered
    /// in Finder (and to match how Review deletes steps). Throws if the raw file couldn't be
    /// moved — the sidebar used to hide the tile anyway, so a failed delete looked like it worked.
    /// The companions are only attempted once the raw file is gone.
    func deleteCapture(rawURL: URL) throws {
        try trashItem(rawURL)
        let folder = rawURL.deletingLastPathComponent()
        let companions = [
            folder.appendingPathComponent(FilenameGenerator.editedName(fromRaw: rawURL.lastPathComponent)),
            annotationsURL(forRaw: rawURL)
        ]
        for url in companions where FileManager.default.fileExists(atPath: url.path) {
            do {
                try trashItem(url)
            } catch {
                NSLog("Clipr: couldn't move \(url.lastPathComponent) to the Trash: \(error)")
            }
        }
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
        guard let data = ImageEncoding.data(source, as: format) else {
            throw StorageError.pngEncodingFailed
        }
        try data.write(to: url, options: .atomic)
    }

    /// Drawn at the image's own pixel density — `lockFocus` would use whichever screen is main,
    /// silently halving a Retina capture on a non-Retina display.
    private static func onWhite(_ image: NSImage) -> NSImage {
        let size = image.size
        guard let context = NSImage.pixelContext(size: size, scale: image.pixelScale),
              let bitmap = image.bitmap else { return image }
        context.setFillColor(.white)
        context.fill(CGRect(origin: .zero, size: size))
        context.draw(bitmap, in: CGRect(origin: .zero, size: size))
        guard let result = context.makeImage() else { return image }
        return NSImage(cgImage: result, size: size)
    }

    private func write(_ image: NSImage, to url: URL, overwrite: Bool = false) throws -> URL {
        guard let pngData = ImageEncoding.png(image) else {
            throw StorageError.pngEncodingFailed
        }
        try Self.createPrivateFolder(url.deletingLastPathComponent())

        // `overwrite` writes to `url` exactly as given (replacing whatever's already there);
        // otherwise resolve a collision by appending a numeric suffix, for callers where a
        // clash means two genuinely different captures landed on the same generated name.
        //
        // Never delete-then-write: that left no file at all when the write failed (disk full,
        // volume ejected), while the editor reported the capture "left unchanged". `writeData`
        // replaces atomically, so on failure the previous file is still there, untouched.
        let finalURL = overwrite ? url : uniqueURL(for: url)
        try writeData(pngData, finalURL)
        Self.restrictToOwner(finalURL)
        return finalURL
    }

    func uniqueURL(for url: URL) -> URL {
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
