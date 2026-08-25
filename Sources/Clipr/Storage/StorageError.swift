import Foundation

enum StorageError: Error {
    case pngEncodingFailed
    case folderCreationFailed(URL)
}
