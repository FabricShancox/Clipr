import Cocoa
import ImageIO

/// Size limits applied before decoding files Clipr didn't just create itself — an image picked
/// with Open Image… or a Recent, and annotation sidecars.
///
/// A PNG of a few kilobytes can declare 60,000 × 60,000 pixels, which a full decode turns into a
/// 14 GB allocation; a sidecar can hold millions of points or absurd coordinates. These come from
/// the user's own folders or files they picked, so the worst case is a hang or crash, but that's
/// still worth refusing up front.
enum DecodeLimits {
    /// Comfortably above any real capture (a 6K display at 2× is about 80 MP).
    static let maxImagePixels = 200_000_000
    static let maxImageSide = 32_768

    static let maxSidecarBytes = 5 * 1024 * 1024
    static let maxAnnotations = 10_000
    static let maxFreehandPoints = 1_000_000
    /// Bound on any coordinate or size in a sidecar, in points.
    static let maxCoordinate: CGFloat = 1_000_000
    static let maxStrokeWidth: CGFloat = 1_000
    static let maxFontSize: CGFloat = 1_000

    /// The pixel size an image file declares, read from its header without decoding it.
    static func declaredPixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return ImageDecoder.pixelSize(of: source)
    }

    static func isAcceptableImageSize(width: Int, height: Int) -> Bool {
        // Both sides are bounded first, so the product can't overflow.
        width > 0 && height > 0 && width <= maxImageSide && height <= maxImageSide
            && width * height <= maxImagePixels
    }

    enum ImageLoad {
        case loaded(NSImage)
        /// Not an image ImageIO can read.
        case unreadable
        case tooLarge(width: Int, height: Int)
    }

    /// Loads an image only after checking the size its header declares.
    static func loadImage(at url: URL) -> ImageLoad {
        guard let size = declaredPixelSize(of: url) else { return .unreadable }
        guard isAcceptableImageSize(width: size.width, height: size.height) else {
            return .tooLarge(width: size.width, height: size.height)
        }
        guard let image = NSImage(contentsOf: url) else { return .unreadable }
        return .loaded(image)
    }

    /// Whether decoded sidecar annotations are within sane bounds.
    static func areAcceptable(_ annotations: [AnnotationObject]) -> Bool {
        guard annotations.count <= maxAnnotations else { return false }
        var points = 0
        func ok(_ value: CGFloat) -> Bool { value.isFinite && abs(value) <= maxCoordinate }
        func ok(_ point: CGPoint) -> Bool { ok(point.x) && ok(point.y) }
        for annotation in annotations {
            let frame = annotation.frame
            guard ok(frame.origin.x), ok(frame.origin.y), ok(frame.size.width), ok(frame.size.height),
                  annotation.strokeWidth.isFinite, annotation.strokeWidth >= 0,
                  annotation.strokeWidth <= maxStrokeWidth else { return false }
            switch annotation.kind {
            case .arrow(let start, let end):
                guard ok(start), ok(end) else { return false }
            case .freehand(let list):
                points += list.count
                guard points <= maxFreehandPoints, list.allSatisfy(ok) else { return false }
            case .text(_, let style):
                guard style.fontSize.isFinite, style.fontSize > 0, style.fontSize <= maxFontSize else { return false }
            default:
                break
            }
        }
        return true
    }
}
