import Cocoa

/// The close-up saved beside a step when "Zoom on click" is on — for guides where the full
/// window is too large to read the control that was clicked.
enum StepZoom {
    static let size = CGSize(width: 400, height: 300)

    /// Top-left image space. Shifted to stay inside the image rather than shrunk, so every zoom
    /// in a session has the same proportions; only an image smaller than the crop limits it.
    /// Rounds x and y to prevent fractional coordinates from expanding the crop via `.integral`.
    static func cropRect(centeredOn p: CGPoint, imageSize: CGSize) -> CGRect {
        let w = min(size.width, imageSize.width), h = min(size.height, imageSize.height)
        let x = min(max(p.x - w / 2, 0), imageSize.width - w).rounded()
        let y = min(max(p.y - h / 2, 0), imageSize.height - h).rounded()
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func image(from image: NSImage, centeredOn p: CGPoint) -> NSImage? {
        CaptureGeometry.cropped(image, to: cropRect(centeredOn: p, imageSize: image.size))?.image
    }
}
