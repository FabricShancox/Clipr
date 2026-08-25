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

    /// Returns `[]` if there's no sidecar yet (a fresh, never-edited capture) or if it fails to
    /// decode — reopening should never hard-fail just because a saved annotation set is missing
    /// or unreadable.
    func loadAnnotations(rawURL: URL) -> [AnnotationObject] {
        guard let data = try? Data(contentsOf: annotationsURL(forRaw: rawURL)) else { return [] }
        return (try? JSONDecoder().decode([AnnotationObject].self, from: data)) ?? []
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
