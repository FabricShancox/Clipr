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

    /// The close-up an export shows: cut from `base` with `annotations` flattened on, so redactions
    /// and other edits apply. `captured` is the close-up saved at capture time; it's only used to
    /// check that the raw pixels under the crop are still the ones that were clicked. Nil when they
    /// aren't (the editor cropped or resized the canvas so the point moved, or the image was
    /// replaced) or the point is outside the image — the click point can't be trusted then.
    static func closeUp(base: NSImage, annotations: [AnnotationObject], clickPoint p: CGPoint, captured: NSImage) -> NSImage? {
        guard CGRect(origin: .zero, size: base.size).contains(p) else { return nil }
        let rect = cropRect(centeredOn: p, imageSize: base.size)
        guard let now = CaptureGeometry.cropped(base, to: rect)?.image.bitmap, let then = captured.bitmap,
              samePixels(now, then) else { return nil }
        let flat = annotations.isEmpty ? base : AnnotationRenderer.flatten(base: base, annotations: annotations)
        return CaptureGeometry.cropped(flat, to: rect)?.image
    }

    /// Same pixel dimensions and every channel within `tolerance` once both are drawn into the same
    /// RGBA space — tolerant of colour-management rounding, not of different content.
    static func samePixels(_ a: CGImage, _ b: CGImage, tolerance: UInt8 = 2) -> Bool {
        guard a.width == b.width, a.height == b.height, let pa = rgba(a), let pb = rgba(b) else { return false }
        return zip(pa, pb).allSatisfy { x, y in (x > y ? x - y : y - x) <= tolerance }
    }

    private static func rgba(_ image: CGImage) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = BitmapContext.rgb(
                width: image.width, height: image.height, data: buffer.baseAddress, bytesPerRow: image.width * 4
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? bytes : nil
    }
}
