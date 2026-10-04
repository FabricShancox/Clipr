import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The one place images become file data.
///
/// Two flavours, deliberately different: an `NSImage` is written through `NSBitmapImageRep`
/// tagged with its point size, so the file records its pixel density (144 dpi for a Retina
/// capture) and reopens — here, in Preview, or pasted into a document — at the size it appeared
/// on screen. A bare `CGImage` (export renders, which are sized in pixels) goes through ImageIO
/// with no density at all.
enum ImageEncoding {
    /// `image`'s full-resolution bitmap encoded as `format`, or nil if it has no bitmap or won't
    /// encode. Same convention as capture: see `NSImage+PixelScale.swift`.
    static func data(_ image: NSImage, as format: ExportFormat = .png) -> Data? {
        guard let bitmap = image.bitmap else { return nil }
        let rep = NSBitmapImageRep(cgImage: bitmap)
        rep.size = image.size
        return rep.representation(using: format.bitmapType, properties: format.properties)
    }

    /// Shorthand for the PNG every capture and step is stored as.
    static func png(_ image: NSImage) -> Data? {
        data(image, as: .png)
    }

    /// `image` encoded by ImageIO as `type` (PNG, JPEG…), with destination `properties` such as
    /// `kCGImageDestinationLossyCompressionQuality`.
    static func data(_ image: CGImage, type: UTType, properties: [CFString: Any] = [:]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
