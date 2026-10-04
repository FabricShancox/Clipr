import Foundation

/// Rendered images keyed by step number. Close-ups get their own map because a step can have both.
struct RenderedImages: Equatable {
    var steps: [Int: GuideImage] = [:]
    var zooms: [Int: GuideImage] = [:]
}
