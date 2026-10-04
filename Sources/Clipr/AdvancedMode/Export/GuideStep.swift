import Foundation

/// One step of a `GuideDocument`.
struct GuideStep: Equatable {
    /// 1-based position in the exported guide, not in the session.
    let number: Int
    /// Inline Markdown, untrusted; nil when the step has no caption.
    let caption: String?
    let appName: String?
    let imageSize: ImageSize
    let image: GuideImageRef
    /// Nil unless close-ups were asked for and this step had one captured (still on disk).
    let zoom: GuideImageRef?
}
