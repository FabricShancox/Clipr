import Foundation

/// Where a step's picture comes from. Rendering (annotations, downsampling, encoding) is left to
/// `GuideImages`, so building a document stays cheap and pure.
enum GuideImageRef: Equatable {
    /// A raw step PNG; its annotation sidecar sits next to it under the usual name.
    case file(URL)
    /// A close-up, cut from the step's annotated image at export time — never the `_zoom.png`
    /// saved at capture, which holds raw pixels that redactions and crops made since don't reach.
    case closeUp(CloseUpSource)
    case missing
}
