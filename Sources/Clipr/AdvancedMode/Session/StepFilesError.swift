import Foundation

/// Why `StepFiles` couldn't move a step's files.
enum StepFilesError: Error, Equatable {
    case trashedFileMissing(String)
}
