import Foundation

/// Finishing touches added to the image only when it's copied to the clipboard — the saved
/// capture itself is never changed. See `AnnotationRenderer.applying(_:to:)`.
struct CopyStyle: Equatable {
    /// A thin grey frame, so a capture of a white page doesn't vanish into the white document or
    /// chat it's pasted into.
    var border = false
    /// A soft drop shadow on transparent padding, so the capture reads as a floating card.
    var shadow = false
}
