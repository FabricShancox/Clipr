import Foundation

extension ImageSize {
    /// The step image's width as a whole percentage of the guide's content width.
    var widthPercent: Int { Int((widthFraction * 100).rounded()) }
}
