import Foundation
import ImageIO

/// Step images and sidecars come from a session folder that may not be the user's own (a synced
/// save folder, a session someone sent) or from a file the user picked. A few-KB PNG can declare
/// 60k × 60k pixels and a full decode would then allocate gigabytes, so dimensions are checked
/// from the header before anything is decoded at full size, and sidecars are size-capped before
/// they're parsed. Stricter per side than `DecodeLimits`, which also bounds every decode
/// `ImageDecoder` makes; the pixel and sidecar caps are shared with it.
enum UntrustedImageLimits {
    static let maxPixelsPerSide = 16_384
    static let maxPixels = DecodeLimits.maxImagePixels
    static let maxSidecarBytes = DecodeLimits.maxSidecarBytes

    static func allows(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && width <= maxPixelsPerSide && height <= maxPixelsPerSide
            && width * height <= maxPixels
    }

    /// Reads only the header.
    static func isSafeToDecode(_ source: CGImageSource) -> Bool {
        guard let size = ImageDecoder.pixelSize(of: source) else { return false }
        return allows(width: size.width, height: size.height)
    }

    static func isSafeToDecode(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return isSafeToDecode(source)
    }

    /// True when `rawURL`'s annotations sidecar exists and is too large to parse safely.
    static func sidecarTooLarge(forRaw rawURL: URL) -> Bool {
        let sidecar = rawURL.deletingLastPathComponent()
            .appendingPathComponent(FilenameGenerator.annotationsName(fromRaw: rawURL.lastPathComponent))
        guard let size = (try? sidecar.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return false }
        return size > maxSidecarBytes
    }
}
