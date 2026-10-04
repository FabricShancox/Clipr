import Foundation
import CoreGraphics

/// What a close-up is rebuilt from. `capturedZoom` is only a reference: it proves the click point
/// still lands on the same pixels it did at capture, and is never exported itself.
struct CloseUpSource: Equatable {
    /// The raw step PNG; its annotation sidecar sits next to it under the usual name.
    let step: URL
    /// The `_zoom.png` written at capture.
    let capturedZoom: URL
    /// Image points, top-left origin, as recorded at capture.
    let clickPoint: CGPoint
}
