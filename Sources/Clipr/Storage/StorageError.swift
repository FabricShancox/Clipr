import Foundation

enum StorageError: Error {
    case pngEncodingFailed
    case folderCreationFailed(URL)
    /// A rename was asked for with a name that has nothing usable left after sanitising — see
    /// `FilenameGenerator.sanitizedBaseName`.
    case invalidFilename(String)
    /// Capture storage only ever writes PNG data, so it refuses to overwrite a file whose name
    /// says it's something else — see `StorageManager.overwriteRawCapture`.
    case notAPNGCapture(URL)
}

extension StorageError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .pngEncodingFailed: return "The image couldn't be encoded as PNG."
        case .folderCreationFailed(let url): return "The folder \(url.lastPathComponent) couldn't be created."
        case .invalidFilename(let name): return "“\(name)” isn't a usable file name."
        case .notAPNGCapture(let url): return "\(url.lastPathComponent) isn't a PNG, so Clipr won't overwrite it."
        }
    }
}
