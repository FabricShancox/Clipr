import Cocoa

/// Captures are sized in points — the size they appeared on screen — and carry every pixel of
/// the display: a full-screen capture on a 2x Retina display is 1710×1069 points backed by a
/// 3420×2138 bitmap. Annotation geometry, the canvas, crop and canvas-resize rects all work in
/// points; anything that touches the bitmap itself converts with `pixelScale`.
///
/// Captures saved before this change were sized 1:1 with their pixels and still load that way
/// (their PNGs are 72 dpi), with `pixelScale` 1, so their saved annotations still line up.
extension NSImage {
    /// The bitmap behind this image, at full resolution.
    var bitmap: CGImage? {
        cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Bitmap pixels per point — 2 for a Retina capture, 1 for older captures. Never below 1, so
    /// a low-resolution image is never rendered smaller than its own pixels.
    var pixelScale: CGFloat {
        guard size.width > 0, let bitmap else { return 1 }
        return max(1, CGFloat(bitmap.width) / size.width)
    }

    /// A point-sized image backed by `bitmap` at `scale` pixels per point.
    convenience init(bitmap: CGImage, scale: CGFloat) {
        let scale = max(scale, 1)
        self.init(cgImage: bitmap, size: NSSize(width: CGFloat(bitmap.width) / scale, height: CGFloat(bitmap.height) / scale))
    }

    /// A blank RGBA context for drawing an image `size` points big at `scale` pixels per point,
    /// already scaled so drawing into it is done in points. Starts fully transparent.
    static func pixelContext(size: CGSize, scale: CGFloat) -> CGContext? {
        guard let context = CGContext(
            data: nil,
            width: max(Int((size.width * scale).rounded()), 1),
            height: max(Int((size.height * scale).rounded()), 1),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        return context
    }
}

extension CGRect {
    /// This rect, in points, as pixels at `scale`.
    func scaled(by scale: CGFloat) -> CGRect {
        CGRect(x: minX * scale, y: minY * scale, width: width * scale, height: height * scale)
    }
}
