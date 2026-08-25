import Cocoa
import SwiftUI

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private var image: NSImage
    private var rawURL: URL
    private let storage: StorageManager
    var onFinished: (() -> Void)?

    init(image: NSImage, rawURL: URL, storage: StorageManager) {
        self.image = image
        self.rawURL = rawURL
        self.storage = storage

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clipr Editor"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        super.init(window: window)

        // windowWillClose(_:) is the single place onFinished fires — Copy/Share leave the
        // window open, so this only fires via the title-bar close button / Cmd+W.
        window.delegate = self

        window.contentView = makeContentView()
        // Opens maximized (screen's visible frame, not true fullscreen) so the capture is
        // visible at its largest size on launch.
        if let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
        } else {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func windowWillClose(_ notification: Notification) {
        onFinished?()
    }

    /// `initialAnnotations`, when omitted, loads whatever was last saved for `rawURL` from its
    /// JSON sidecar (`StorageManager.loadAnnotations`) — empty for a capture that's never been
    /// edited, or the exact set restored for one that has. `applyCrop`/`applyCanvasResize` pass
    /// an explicit (already-remapped) array instead, since loading from disk there would fetch
    /// the pre-crop/resize geometry.
    private func makeContentView(initialAnnotations: [AnnotationObject]? = nil) -> NSHostingView<EditorView> {
        NSHostingView(rootView: EditorView(
            image: image,
            currentURL: rawURL,
            recentCaptures: recentCaptures(in: storage.baseFolder),
            annotations: initialAnnotations ?? storage.loadAnnotations(rawURL: rawURL),
            onOpenCapture: { [weak self] url, currentAnnotations in self?.loadCapture(url, previousAnnotations: currentAnnotations) },
            onAutoSave: { [weak self] forURL, annotations in self?.autoSave(for: forURL, annotations: annotations) },
            onCopy: { [weak self] annotations in self?.copy(annotations: annotations) },
            onShare: { [weak self] annotations in self?.share(annotations: annotations) },
            onCropApplied: { [weak self] rendererRect, annotations in self?.applyCrop(rendererRect: rendererRect, annotations: annotations) },
            onCanvasResize: { [weak self] topLeftRect, annotations in self?.applyCanvasResize(topLeftRect: topLeftRect, annotations: annotations) },
            onDeleteCapture: { [weak self] url in self?.storage.deleteCapture(rawURL: url) }
        ))
    }

    /// Fired ~800ms after the last edit settles (see `EditorView.scheduleAutoSave`). `forURL` is
    /// the URL that debounce was scheduled against — since that `Task` isn't cancelled by a
    /// content-view swap (`loadCapture`/`applyCrop`/`applyCanvasResize`), a debounce left over
    /// from a since-abandoned capture must not overwrite whatever `rawURL` has since moved on to;
    /// comparing against the current `rawURL` makes a stale request a harmless no-op. Failures
    /// are logged, not alerted, since this can fire often.
    private func autoSave(for forURL: URL, annotations: [AnnotationObject]) {
        guard forURL == rawURL else { return }
        let flattened = AnnotationRenderer.flatten(base: image, annotations: annotations)
        do {
            _ = try storage.saveEditedCapture(flattened, rawURL: rawURL)
            storage.copyToClipboard(flattened)
            // Persists the actual editable annotation objects (not just the flattened preview)
            // so reopening this capture later — from Recents, or after relaunching Clipr —
            // restores them instead of showing a plain, no-longer-editable image. This is what
            // makes returning to a previously-edited capture not read as "losing" the edits.
            try storage.saveAnnotations(annotations, rawURL: rawURL)
        } catch {
            NSLog("Clipr: auto-save failed: \(error)")
        }
    }

    private func copy(annotations: [AnnotationObject]) {
        let flattened = AnnotationRenderer.flatten(base: image, annotations: annotations)
        storage.copyToClipboard(flattened)
    }

    /// `rendererRect` arrives in `AnnotationObject.frame`'s space — origin bottom-left, y up —
    /// but `CaptureGeometry.cropped` expects top-left/y-down; flipping it needs `image.size.height`,
    /// which only this controller (not `EditorView`) has an up-to-date mutable handle on across
    /// crops, so the conversion lives here rather than in `EditorView` or `CaptureGeometry`.
    private func applyCrop(rendererRect: CGRect, annotations: [AnnotationObject]) {
        let oldHeight = image.size.height
        let topLeftRect = CGRect(
            x: rendererRect.origin.x,
            y: oldHeight - rendererRect.origin.y - rendererRect.height,
            width: rendererRect.width,
            height: rendererRect.height
        )
        guard let cropped = CaptureGeometry.cropped(image, to: topLeftRect) else { return }
        image = cropped
        let delta = CaptureGeometry.rendererDelta(oldHeight: oldHeight, newTopLeftOrigin: topLeftRect.origin, newSize: topLeftRect.size)
        let remapped = CaptureGeometry.remapAnnotations(annotations, delta: delta, newSize: topLeftRect.size)
        autoSave(for: rawURL, annotations: remapped)
        window?.contentView = makeContentView(initialAnnotations: remapped)
    }

    /// `topLeftRect` is in top-left/y-down space (matching the corner handles in
    /// `EditorView.canvasResizeHandles`) and, unlike a plain crop rect, may extend beyond the
    /// current image's own bounds (an outward drag) or be smaller (an inward drag) — see
    /// `CaptureGeometry.resizedCanvas` for how that single operation handles both.
    private func applyCanvasResize(topLeftRect: CGRect, annotations: [AnnotationObject]) {
        let oldHeight = image.size.height
        let delta = CaptureGeometry.rendererDelta(oldHeight: oldHeight, newTopLeftOrigin: topLeftRect.origin, newSize: topLeftRect.size)
        guard let resized = CaptureGeometry.resizedCanvas(image, to: topLeftRect, delta: delta) else { return }
        image = resized
        let remapped = CaptureGeometry.remapAnnotations(annotations, delta: delta, newSize: topLeftRect.size)
        autoSave(for: rawURL, annotations: remapped)
        window?.contentView = makeContentView(initialAnnotations: remapped)
    }

    private func share(annotations: [AnnotationObject]) {
        guard let contentView = window?.contentView else { return }
        let flattened = AnnotationRenderer.flatten(base: image, annotations: annotations)
        let picker = NSSharingServicePicker(items: [flattened])
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .maxY)
    }

    /// Loads a different capture into THIS window (replacing image/rawURL and rebuilding the
    /// content view) rather than opening a second editor window — clicking a "Recent" thumbnail
    /// browses in place. The incoming capture's own annotations, if any, are restored from its
    /// JSON sidecar by `makeContentView`'s default. `previousAnnotations` — the outgoing view's
    /// current annotations — are flushed synchronously against the OLD `rawURL` first, before
    /// it's reassigned, so a very recent edit that hadn't reached its debounce yet isn't lost.
    private func loadCapture(_ url: URL, previousAnnotations: [AnnotationObject]) {
        autoSave(for: rawURL, annotations: previousAnnotations)
        guard let newImage = NSImage(contentsOf: url) else { return }
        image = newImage
        rawURL = url
        window?.contentView = makeContentView()
    }

}
