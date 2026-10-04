import Cocoa

/// One Advanced Mode step's captured image and where it sits on screen.
struct CapturedFrame {
    let image: NSImage
    /// Quartz global position of the image's top-left corner — what `StepGeometry` subtracts.
    let origin: CGPoint
    var appName: String?
    /// False when the image isn't of what was clicked (the clicked window closed before the
    /// capture), so the click point means nothing in it.
    var marksClick = true
}
