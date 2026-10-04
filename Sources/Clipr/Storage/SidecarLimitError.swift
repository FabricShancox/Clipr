import Foundation

/// Why a sidecar was refused before or after decoding — reported as `.corrupt`, so the editor
/// sets it aside rather than overwriting it.
enum SidecarLimitError: Error, LocalizedError {
    case tooLarge(bytes: Int)
    case outOfRange

    var errorDescription: String? {
        switch self {
        case .tooLarge(let bytes): return "The annotations file is too large (\(bytes) bytes)."
        case .outOfRange: return "The annotations file holds values outside the supported range."
        }
    }
}
