import Foundation

enum PDFExportError: Error, Equatable {
    case loadFailed
    case timedOut
    case printFailed
    /// `export` was called a second time on the same exporter.
    case alreadyUsed
    /// `cancel()` was called.
    case cancelled
}
