import Cocoa

/// Pure crop/canvas-resize math and pixel operations, extracted out of `EditorWindowController`
/// so they can be unit tested directly instead of only indirectly through UI interaction.
struct CaptureGeometry {
    /// The renderer-space (bottom-left origin, y up) translation that carries a point from the
    /// OLD canvas into the NEW one, given the new canvas's origin and size in top-left/y-down
    /// space (`origin`/`newSize` — the same space crop/resize rects are computed in). Deriving
    /// this requires converting a physical point through both origins' conventions: old
    /// renderer-space -> old top-left-space (subtract origin) -> new top-left-space -> new
    /// renderer-space. Working through that algebra collapses to a single constant offset per
    /// axis (this operation is always a pure translation, never a scale) — used both to
    /// translate existing `AnnotationObject`s (`remapAnnotations`) and, identically, to position
    /// the old image when compositing it into the resized canvas (`resizedCanvas`), since both
    /// are the same coordinate-space translation applied to different things.
    static func rendererDelta(oldHeight: CGFloat, newTopLeftOrigin origin: CGPoint, newSize: CGSize) -> CGPoint {
        CGPoint(x: -origin.x, y: origin.y + newSize.height - oldHeight)
    }

    /// Shared by crop and canvas-resize: both change the base image's origin and size, and both
    /// should carry existing annotations along rather than discard them, as long as the
    /// annotation still falls (at least partly) within the new bounds.
    static func remapAnnotations(_ annotations: [AnnotationObject], delta: CGPoint, newSize: CGSize) -> [AnnotationObject] {
        let newCanvasBounds = CGRect(origin: .zero, size: newSize)
        return annotations
            .map { $0.translated(by: delta) }
            .filter { $0.frame.intersects(newCanvasBounds) }
    }

    /// `topLeftRect` arrives in top-left/y-down space (matching `AnnotationCanvasView`'s crop-drag
    /// rect after `EditorWindowController` flips it) — `CGImage.cropping(to:)` expects that same
    /// convention (verified empirically; not the same as the renderer's own bottom-left/y-up
    /// space `AnnotationObject.frame` uses).
    static func cropped(_ image: NSImage, to topLeftRect: CGRect) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = cgImage.cropping(to: topLeftRect) else { return nil }
        return NSImage(cgImage: cropped, size: topLeftRect.size)
    }

    /// Composites `image` into a new, otherwise-transparent canvas of `topLeftRect.size`, offset
    /// by `delta` (see `rendererDelta`) — the single operation behind canvas-resize handles: an
    /// inward drag reduces to an ordinary crop; an outward drag leaves the newly-added area
    /// transparent, since a freshly created `CGContext` starts fully transparent and the old
    /// image simply doesn't reach that far.
    ///
    /// `flipped: false` matches `AnnotationRenderer.flatten`'s empirically-verified convention
    /// (bottom-left origin, y up — the native match for a raw `CGContext`). An earlier version of
    /// this used `flipped: true` on the theory that `NSImage.draw(in:)` always draws right-side-up
    /// regardless of context flippedness and only the rect origin's meaning would change — that
    /// theory was wrong in practice (it flipped the image upside down), so this reuses the one
    /// drawing convention already proven to work correctly in this codebase.
    static func resizedCanvas(_ image: NSImage, to topLeftRect: CGRect, delta: CGPoint) -> NSImage? {
        let pixelWidth = max(Int(topLeftRect.width.rounded()), 1)
        let pixelHeight = max(Int(topLeftRect.height.rounded()), 1)
        guard let context = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: CGRect(x: delta.x, y: delta.y, width: image.size.width, height: image.size.height))
        NSGraphicsContext.restoreGraphicsState()

        guard let resized = context.makeImage() else { return nil }
        return NSImage(cgImage: resized, size: topLeftRect.size)
    }
}
