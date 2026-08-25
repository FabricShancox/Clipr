import Cocoa

enum StorageError: Error {
    case pngEncodingFailed
    case folderCreationFailed(URL)
}

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

    func saveEditedCapture(_ image: NSImage, rawURL: URL) throws -> URL {
        let editedName = FilenameGenerator.editedName(fromRaw: rawURL.lastPathComponent)
        let editedURL = rawURL.deletingLastPathComponent().appendingPathComponent(editedName)
        return try write(image, to: editedURL)
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

    private func write(_ image: NSImage, to url: URL) throws -> URL {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw StorageError.pngEncodingFailed
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Resolve filename collisions by appending numeric suffix if needed
        let finalURL = uniqueURL(for: url)
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
