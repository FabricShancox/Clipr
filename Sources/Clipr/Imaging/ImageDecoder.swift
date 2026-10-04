// Sources/Clipr/Imaging/ImageDecoder.swift
import Foundation
import CoreGraphics
import ImageIO

/// ImageIO header reads and downsampled decodes, in one place so every one of them is bounded by
/// `DecodeLimits` before any pixels are decoded.
enum ImageDecoder {
    /// The first image's header properties (pixel size, DPI, orientation), read without decoding.
    static func properties(of source: CGImageSource) -> [CFString: Any]? {
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    /// The pixel size the first image's header declares.
    static func pixelSize(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = properties(of: source),
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    /// The first image decoded upright (EXIF orientation applied) with its long side at most
    /// `maxPixelSize`. `CGImageSourceCreateThumbnailAtIndex` subsamples during the decode, so a
    /// huge capture is never materialised at full size. Nil if it won't decode or its header
    /// declares more than `DecodeLimits` allows. Safe off the main thread.
    static func thumbnail(_ source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        guard let size = pixelSize(of: source),
              DecodeLimits.isAcceptableImageSize(width: size.width, height: size.height) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func thumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source, maxPixelSize: maxPixelSize)
    }
}
