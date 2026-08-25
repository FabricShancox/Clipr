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

        // Delegate assignment needs `self` to exist, so it happens after super.init.
        // windowWillClose(_:) is the single place onFinished fires — Save/Copy/Share never
        // close the window themselves (the editor stays open after any of them, so you can
        // keep annotating), so onFinished now fires only via the native title-bar close
        // button / Cmd+W, which is also what makes this editor's own "Discard" path.
        window.delegate = self

        window.contentView = makeContentView()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func windowWillClose(_ notification: Notification) {
        onFinished?()
    }

    private func makeContentView() -> NSHostingView<EditorView> {
        NSHostingView(rootView: EditorView(
            image: image,
            currentURL: rawURL,
            recentCaptures: EditorWindowController.recentCaptures(in: storage.baseFolder, excluding: rawURL),
            onOpenCapture: { [weak self] url in self?.loadCapture(url) },
            onAutoSave: { [weak self] annotations in self?.autoSave(annotations: annotations) },
            onCopy: { [weak self] annotations in self?.copy(annotations: annotations) },
            onShare: { [weak self] annotations in self?.share(annotations: annotations) },
            onCropApplied: { [weak self] rendererRect in self?.applyCrop(rendererRect: rendererRect) }
        ))
    }

    /// Fired ~800ms after the last edit settles (see `EditorView.scheduleAutoSave`) rather than
    /// from an explicit Save button — there is no manual Save anymore, so switching to a
    /// different Recent capture (which discards in-memory undo history, see `loadCapture`) never
    /// loses anything: the edit is already flattened to disk and the clipboard by the time that
    /// happens. Failures are logged, not alerted — an alert firing on every debounced write for a
    /// persistent problem (e.g. a full disk) would be far more disruptive than the old one-shot
    /// manual Save's alert ever was.
    private func autoSave(annotations: [AnnotationObject]) {
        let flattened = AnnotationRenderer.flatten(base: image, annotations: annotations)
        do {
            _ = try storage.saveEditedCapture(flattened, rawURL: rawURL)
            storage.copyToClipboard(flattened)
        } catch {
            NSLog("Clipr: auto-save failed: \(error)")
        }
    }

    private func copy(annotations: [AnnotationObject]) {
        let flattened = AnnotationRenderer.flatten(base: image, annotations: annotations)
        storage.copyToClipboard(flattened)
    }

    /// `rendererRect` arrives in `AnnotationObject.frame`'s space — origin bottom-left, y up
    /// (see `AnnotationCanvasView`'s coordinate-space doc comment) — but `CGImage.cropping(to:)`
    /// expects origin top-left, y down (verified empirically; not the same convention as the
    /// renderer). Flipping it needs `image.size.height`, which only this controller (not
    /// `EditorView`) has an up-to-date mutable handle on across crops, so the conversion lives
    /// here rather than in `EditorView`.
    ///
    /// Cropping discards the current annotations: their frames were measured against the old,
    /// larger canvas and would no longer line up with the smaller cropped one. This matches
    /// `loadCapture`'s existing precedent of resetting annotations on any base-image swap.
    private func applyCrop(rendererRect: CGRect) {
        let topLeftRect = CGRect(
            x: rendererRect.origin.x,
            y: image.size.height - rendererRect.origin.y - rendererRect.height,
            width: rendererRect.width,
            height: rendererRect.height
        )
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = cgImage.cropping(to: topLeftRect) else { return }
        image = NSImage(cgImage: cropped, size: topLeftRect.size)
        autoSave(annotations: [])
        window?.contentView = makeContentView()
    }

    private func share(annotations: [AnnotationObject]) {
        guard let contentView = window?.contentView else { return }
        let flattened = AnnotationRenderer.flatten(base: image, annotations: annotations)
        let picker = NSSharingServicePicker(items: [flattened])
        picker.show(relativeTo: .zero, of: contentView, preferredEdge: .maxY)
    }

    /// Loads a different capture into THIS window (replacing image/rawURL and rebuilding the
    /// content view) rather than opening a second editor window — clicking a "Recent" thumbnail
    /// browses in place, matching how a single-document image editor behaves. This intentionally
    /// discards the current annotations/undo history: switching to a different screenshot is a
    /// fresh start, not a continuation of the one being left.
    private func loadCapture(_ url: URL) {
        guard let newImage = NSImage(contentsOf: url) else { return }
        image = newImage
        rawURL = url
        window?.contentView = makeContentView()
    }

    /// Snapshot of recent top-level captures in the save folder, newest first, for the sidebar.
    /// Deliberately a one-time list at content-view-build time rather than a live-updating one —
    /// simple, and rebuilt fresh every time `loadCapture` swaps in a new image anyway.
    private static func recentCaptures(in folder: URL, excluding current: URL, limit: Int = 20) -> [URL] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        let pngs = entries.filter { $0.pathExtension.lowercased() == "png" && $0 != current }
        let sorted = pngs.sorted { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return dateA > dateB
        }
        return [current] + Array(sorted.prefix(limit))
    }
}
