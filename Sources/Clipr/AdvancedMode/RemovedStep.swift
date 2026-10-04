import Foundation

/// A step taken out of a manifest, with where it was, so undo can put it back in place.
struct RemovedStep: Equatable {
    let record: StepRecord
    let index: Int
}
