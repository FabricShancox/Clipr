import Foundation
import CoreGraphics

/// `steps` order is display order, so steps can be reordered later without renaming files.
struct SessionManifest: Codable, Equatable {
    var version: Int
    var createdAt: Date
    var steps: [StepRecord]

    init(createdAt: Date, steps: [StepRecord] = []) {
        version = 1
        self.createdAt = createdAt
        self.steps = steps
    }
}
