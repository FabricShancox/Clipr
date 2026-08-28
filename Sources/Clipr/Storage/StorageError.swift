import Foundation

enum StorageError: Error {
    case pngEncodingFailed
    case folderCreationFailed(URL)
    /// A rename was asked for with a name that has nothing usable left after sanitising — see
    /// `FilenameGenerator.sanitizedBaseName`.
    case invalidFilename(String)
}
