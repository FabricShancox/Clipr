import Foundation

enum GuideExportError: LocalizedError, Equatable {
    case cancelled
    case destinationNotWritable(String)
    case writeFailed(String)
    case pdfFailed
    case clipboardFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Export cancelled."
        case .destinationNotWritable(let reason): return "Couldn't write to the chosen location. \(reason)"
        case .writeFailed(let reason): return "Couldn't finish the export. \(reason)"
        case .pdfFailed: return "Couldn't create the PDF. Try exporting as HTML instead."
        case .clipboardFailed: return "Couldn't copy the guide to the clipboard."
        }
    }
}
