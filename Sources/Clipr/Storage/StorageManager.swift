import Cocoa

enum StorageError: Error {
    case pngEncodingFailed
    case folderCreationFailed(URL)
}

final class StorageManager {
    let baseFolder: URL

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
        try pngData.write(to: url)
        return url
    }
}
