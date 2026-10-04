import Cocoa

/// Crop and canvas-resize: both rewrite the raw capture and remap the annotations.
extension EditorWindowController {
    /// `rendererRect` arrives in `AnnotationObject.frame`'s space — origin bottom-left, y up —
    /// but `CaptureGeometry.cropped` expects top-left/y-down; flipping it needs `image.size.height`,
    /// which only this controller (not `EditorView`) has an up-to-date mutable handle on across
    /// crops, so the conversion lives here rather than in `EditorView` or `CaptureGeometry`.
    func applyCrop(rendererRect: CGRect, annotations: [AnnotationObject]) {
        let oldHeight = image.size.height
        let topLeftRect = CGRect(
            x: rendererRect.origin.x,
            y: oldHeight - rendererRect.origin.y - rendererRect.height,
            width: rendererRect.width,
            height: rendererRect.height
        )
        // `rect` is the crop that actually happened, which differs from the requested one when the
        // drag ran past the canvas edge — the delta and new canvas size must come from it.
        guard let (cropped, rect) = CaptureGeometry.cropped(image, to: topLeftRect) else { return }
        guard writeBaseImage(cropped, operation: "crop") else { return }
        image = cropped
        let delta = CaptureGeometry.rendererDelta(oldHeight: oldHeight, newTopLeftOrigin: rect.origin, newSize: rect.size)
        let remapped = CaptureGeometry.remapAnnotations(annotations, delta: delta, newSize: rect.size)
        persist(remapped)
        window?.contentView = makeContentView(initialAnnotations: remapped)
    }

    /// Writes a new base image over the raw capture, reporting whether it stuck.
    ///
    /// Crop and canvas-resize replace the capture's own pixels, so the raw file has to change too
    /// or reopening would restore the original. The write goes FIRST and the caller bails out on
    /// failure, leaving the in-memory image untouched — a half-applied operation, where the screen
    /// shows a cropped image that disk disagrees with, is worse than one that visibly did nothing.
    private func writeBaseImage(_ newImage: NSImage, operation: String) -> Bool {
        do {
            try storage.overwriteRawCapture(newImage, rawURL: rawURL)
            // The base image changed, so the flattened export is out of date even if no annotation
            // did — crop and canvas-resize both land here.
            flattenedIsStale = true
            // The Recents tile seeds from this cache by URL, and the URL hasn't changed, so
            // without this it kept showing the uncropped image for the rest of the session.
            ThumbnailCache.shared.remove(rawURL)
            return true
        } catch {
            NSLog("Clipr: \(operation) failed to write \(rawURL.lastPathComponent): \(error)")
            Alerts.present("Couldn't \(operation) this capture",
                           "\(rawURL.lastPathComponent) could not be written, so it was left unchanged.\n\n\(error.localizedDescription)",
                           on: window)
            return false
        }
    }

    /// `topLeftRect` is in top-left/y-down space (matching the corner handles in
    /// `EditorView.canvasResizeHandles`) and, unlike a plain crop rect, may extend beyond the
    /// current image's own bounds (an outward drag) or be smaller (an inward drag) — see
    /// `CaptureGeometry.resizedCanvas` for how that single operation handles both.
    func applyCanvasResize(topLeftRect: CGRect, annotations: [AnnotationObject]) {
        let oldHeight = image.size.height
        let delta = CaptureGeometry.rendererDelta(oldHeight: oldHeight, newTopLeftOrigin: topLeftRect.origin, newSize: topLeftRect.size)
        guard let resized = CaptureGeometry.resizedCanvas(image, to: topLeftRect, delta: delta) else { return }
        guard writeBaseImage(resized, operation: "resize") else { return }
        image = resized
        let remapped = CaptureGeometry.remapAnnotations(annotations, delta: delta, newSize: topLeftRect.size)
        persist(remapped)
        window?.contentView = makeContentView(initialAnnotations: remapped)
    }

    /// `buttonFrame` is in SwiftUI's global (top-left origin) space for the hosting view; the
    /// picker is anchored to it so it pops from the Share button, not the window's corner.
    func share(annotations: [AnnotationObject], from buttonFrame: CGRect) {
        guard let contentView = window?.contentView else { return }
        let flattened = AnnotationRenderer.flatten(base: image, annotations: annotations)
        let picker = NSSharingServicePicker(items: [flattened])
        var anchor = buttonFrame
        if !contentView.isFlipped {
            anchor.origin.y = contentView.bounds.height - buttonFrame.maxY
        }
        if anchor.isEmpty { anchor = CGRect(x: contentView.bounds.maxX - 60, y: 0, width: 1, height: 1) }
        // Below the button: the bottom edge is maxY in a flipped view, minY otherwise.
        picker.show(relativeTo: anchor, of: contentView, preferredEdge: contentView.isFlipped ? .maxY : .minY)
    }
}
