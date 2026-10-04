import AppKit

/// Where a step's files went when it was deleted, so undo can move them back.
struct TrashedStep: Equatable {
    struct Move: Equatable {
        let original: URL
        let trashed: URL
    }
    let file: String
    let moves: [Move]
}
