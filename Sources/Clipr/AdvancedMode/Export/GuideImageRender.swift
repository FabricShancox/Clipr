import AppKit

/// The outcome of rendering one step image.
struct GuideImageRender {
    /// Nil when the image is missing or won't decode.
    let image: GuideImage?
    /// The step's annotation sidecar exists but couldn't be read. `image` is then nil: the raw capture
    /// may hold content a redaction was covering, so it is never exported.
    let sidecarDamaged: Bool
}
