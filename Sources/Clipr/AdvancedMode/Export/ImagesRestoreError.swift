import Foundation

/// The new guide.md couldn't be placed and the user's old `images/` couldn't be put back either:
/// the old images stay in the hidden backup folder, which is named so the user can find it.
struct ImagesRestoreError: LocalizedError, Equatable {
    let backup: URL

    var errorDescription: String? {
        "The guide couldn't be placed, and your old images couldn't be put back. They were kept at “\(backup.path)”."
    }
}
