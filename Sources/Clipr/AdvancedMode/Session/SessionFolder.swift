import Foundation

/// Creating a new session's folder. Never reuses one that exists: the name has one-second
/// resolution (and repeats when the clock goes back an hour), and a reused folder would have its
/// `session.json` overwritten and its old PNGs mixed into the new session.
enum SessionFolder {
    /// Owner-only, so screenshots and typed-text captions aren't readable by other users when the
    /// save folder is somewhere shared (`/Users/Shared`, an external disk).
    static let folderPermissions = 0o700
    static let filePermissions = 0o600

    static func create(in base: URL, date: Date, fileManager: FileManager = .default) throws -> URL {
        let name = FilenameGenerator.sessionFolderName(date: date)
        do {
            try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        } catch {
            throw StorageError.folderCreationFailed(base)
        }
        for attempt in 1...1000 {
            let folder = base.appendingPathComponent(attempt == 1 ? name : "\(name)_\(attempt)")
            do {
                // Not intermediate: creating the leaf must fail if it already exists.
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: folderPermissions])
                return folder
            } catch CocoaError.fileWriteFileExists {
                continue
            } catch {
                throw StorageError.folderCreationFailed(folder)
            }
        }
        throw StorageError.folderCreationFailed(base.appendingPathComponent(name))
    }

    /// Owner read/write only. Best effort: a volume without POSIX permissions keeps its own.
    static func restrict(_ url: URL, fileManager: FileManager = .default) {
        try? fileManager.setAttributes([.posixPermissions: filePermissions], ofItemAtPath: url.path)
    }
}
