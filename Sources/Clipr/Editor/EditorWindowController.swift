import Cocoa
import SwiftUI

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private var image: NSImage
    private var rawURL: URL
    private let storage: StorageManager
    var onFinished: (() -> Void)?

    /// The live annotations of the currently-shown content view, updated synchronously on every
    /// change. `flushPendingSave` writes these when the window closes or the app quits, which is
    /// when the 800ms debounce would otherwise be abandoned unwritten.
    private var latestAnnotations: [AnnotationObject] = []
    /// Carried across a rename's content-view rebuild so undo history survives it. See
    /// `EditorHistory` for why only rename gets this.
    private var latestHistory = EditorHistory()

    /// Bumped on every content-view swap (crop, canvas-resize, rename, opening another capture).
    /// A debounced save carries the generation it was scheduled under, so one left in flight from
    /// a view that has since been replaced can be told apart from a current one. Comparing URLs
    /// alone is not enough: crop and canvas-resize keep the same `rawURL`, so a pre-crop debounce
    /// would otherwise pass the URL check and overwrite the correctly-remapped save with
    /// annotations still in pre-crop coordinates.
    private var generation = 0

    /// Whether `_edited.png` no longer reflects the current annotations, so a write is worth doing.
    private var flattenedIsStale = false
    private var lastFlattenedWrite = Date.distantPast
    /// Minimum gap between flattened writes while the user is actively editing. Re-encoding a
    /// full-screen Retina capture costs ~250ms on the main thread (measured: 11ms at 1280x800,
    /// 77ms at 3420x2146, 248ms at 6000x4000) and the debounce fires every 800ms, so writing it on
    /// every settled edit made the editor hitch continuously on large captures.
    private static let flattenedWriteInterval: TimeInterval = 3

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
        // Before `onFinished` — that releases this controller, and with it any in-flight debounce.
        flushPendingSave()
        onFinished?()
    }

    /// Switching away from the editor is the point at which the user is most likely to go and use
    /// the exported file, so bring it up to date now rather than leaving it a few seconds behind.
    /// No-ops when nothing has changed since the last write.
    func windowDidResignKey(_ notification: Notification) {
        flushPendingSave()
    }

    /// Writes the current annotations immediately, bypassing the debounce.
    ///
    /// Without this, editing and then closing the window (or quitting) inside the 800ms debounce
    /// lost the edit outright: the pending `Task` holds the view weakly and the controller is
    /// released the moment `onFinished` runs, so the scheduled write simply never happened, with
    /// nothing shown to the user. Called from `windowWillClose` and from
    /// `AppDelegate.applicationShouldTerminate`.
    func flushPendingSave() {
        persist(latestAnnotations)
    }

    /// `initialAnnotations`, when omitted, loads whatever was last saved for `rawURL` from its
    /// JSON sidecar (`StorageManager.loadAnnotations`) — empty for a capture that's never been
    /// edited, or the exact set restored for one that has. `applyCrop`/`applyCanvasResize` pass
    /// an explicit (already-remapped) array instead, since loading from disk there would fetch
    /// the pre-crop/resize geometry.
    private func makeContentView(
        initialAnnotations: [AnnotationObject]? = nil,
        history: EditorHistory = EditorHistory()
    ) -> NSHostingView<EditorView> {
        generation += 1
        let generation = self.generation
        latestHistory = history
        // Seeded here rather than left over from the previous view: closing straight after
        // switching captures would otherwise flush the OLD capture's annotations onto the new one.
        let resolved = initialAnnotations ?? loadAnnotationsPreservingCorrupt()
        latestAnnotations = resolved

        return NSHostingView(rootView: EditorView(
            image: image,
            currentURL: rawURL,
            recentCaptures: recentCaptures(in: storage.baseFolder),
            annotations: resolved,
            undoStack: history.undo,
            redoStack: history.redo,
            onOpenCapture: { [weak self] url, currentAnnotations in self?.loadCapture(url, previousAnnotations: currentAnnotations) },
            onAutoSave: { [weak self] forURL, annotations in
                self?.autoSave(for: forURL, annotations: annotations, generation: generation)
            },
            onAnnotationsChanged: { [weak self] annotations in
                guard let self, generation == self.generation else { return }
                self.latestAnnotations = annotations
                self.flattenedIsStale = true
            },
            onHistoryChanged: { [weak self] history in
                guard let self, generation == self.generation else { return }
                self.latestHistory = history
            },
            onCopy: { [weak self] annotations in self?.copy(annotations: annotations) },
            onSaveAs: { [weak self] annotations in self?.saveAs(annotations: annotations) },
            onRevealInFinder: { url in NSWorkspace.shared.activateFileViewerSelecting([url]) },
            onShare: { [weak self] annotations in self?.share(annotations: annotations) },
            onCropApplied: { [weak self] rendererRect, annotations in self?.applyCrop(rendererRect: rendererRect, annotations: annotations) },
            onCanvasResize: { [weak self] topLeftRect, annotations in self?.applyCanvasResize(topLeftRect: topLeftRect, annotations: annotations) },
            onDeleteCapture: { [weak self] url in self?.storage.deleteCapture(rawURL: url) },
            onRename: { [weak self] url, newName, annotations in self?.rename(url, to: newName, annotations: annotations) }
        ))
    }

    /// Loads the capture's saved annotations, handling the case where the sidecar exists but won't
    /// decode — a build that changed the annotation format, or a truncated file.
    ///
    /// Such a capture used to open looking empty, and the first edit then auto-saved over the
    /// sidecar, destroying whatever it held. The file is moved aside first so nothing is lost, and
    /// the user is told rather than left to discover it.
    private func loadAnnotationsPreservingCorrupt() -> [AnnotationObject] {
        switch storage.readAnnotations(rawURL: rawURL) {
        case .missing:
            return []
        case .loaded(let annotations):
            return annotations
        case .corrupt(let error):
            let name = rawURL.lastPathComponent
            let backup = storage.quarantineAnnotations(rawURL: rawURL)
            NSLog("Clipr: unreadable annotations for \(name): \(error)")
            // Deferred: this runs from `makeContentView`, which is called during `init` before the
            // window is on screen, and a sheet can't be presented on a window that isn't showing.
            DispatchQueue.main.async { [weak self] in
                let alert = NSAlert()
                alert.messageText = "Saved annotations for this capture couldn't be read"
                alert.informativeText = backup.map {
                    "\(name) has opened without them. The unreadable file was kept as \($0.lastPathComponent) in case it can be recovered."
                } ?? "\(name) has opened without them."
                alert.alertStyle = .warning
                if let window = self?.window, window.isVisible {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
            }
            return []
        }
    }

    /// Renames the open capture from the header field. `annotations` are flushed synchronously
    /// against the OLD `rawURL` first — the same reason `loadCapture` does it — so an edit that
    /// hadn't reached its debounce yet is written before the files move, rather than firing
    /// afterwards against a path that no longer exists and being dropped by `autoSave`'s guard.
    ///
    /// Rebuilding the content view re-reads Recents, so the sidebar picks up the new name too.
    /// Unlike auto-save this is a direct user action, so a failure is surfaced rather than logged.
    private func rename(_ url: URL, to newName: String, annotations: [AnnotationObject]) {
        guard url == rawURL else { return }
        persist(annotations)
        do {
            // A rename changes nothing about the image or its annotations, so the undo history is
            // carried across the rebuild rather than discarded.
            let history = latestHistory
            rawURL = try storage.renameCapture(rawURL: rawURL, toBaseName: newName)
            window?.contentView = makeContentView(initialAnnotations: annotations, history: history)
        } catch {
            NSLog("Clipr: rename failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Couldn't rename this capture"
            alert.informativeText = "\(url.lastPathComponent) was left unchanged.\n\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }
    }

    /// Fired ~800ms after the last edit settles (see `EditorView.scheduleAutoSave`). That `Task`
    /// isn't cancelled by a content-view swap, so a debounce left over from a since-abandoned view
    /// must not overwrite what the window has moved on to. `forURL` catches a switch to a
    /// different capture; `generation` catches crop and canvas-resize, which keep the same URL but
    /// remap every annotation, so a stale save would write pre-crop geometry over the good one.
    private func autoSave(for forURL: URL, annotations: [AnnotationObject], generation: Int) {
        guard generation == self.generation, forURL == rawURL else { return }
        persist(annotations, flattened: .throttled)
    }

    /// How eagerly `persist` rewrites the flattened `_edited.png`.
    private enum FlattenedWrite {
        /// Write it now if anything has changed — for the moments where the file on disk has to be
        /// current: closing, quitting, switching capture, or changing the base image.
        case now
        /// Skip it if one was written in the last few seconds. Used by the debounced auto-save,
        /// which fires far too often to re-encode a large capture every time.
        case throttled
    }

    /// Writes the flattened preview and the annotations sidecar for the CURRENT capture. Callers
    /// inside this class use it directly — they only ever run for the live view, so they need no
    /// staleness check. Failures are logged, not alerted, since this can fire often.
    private func persist(_ annotations: [AnnotationObject], flattened: FlattenedWrite = .now) {
        do {
            // The sidecar is what actually preserves the user's work — it restores editable
            // annotations on reopen and costs well under a millisecond — so it is written every
            // time. `_edited.png` is a derived export and may lag by a few seconds during active
            // editing; it is brought up to date whenever it matters (see `FlattenedWrite.now`),
            // and a stale one is regenerated from the sidecar anyway.
            try storage.saveAnnotations(annotations, rawURL: rawURL)

            let dueForWrite = flattened == .now
                || Date().timeIntervalSince(lastFlattenedWrite) >= Self.flattenedWriteInterval
            guard flattenedIsStale, dueForWrite else { return }

            let rendered = AnnotationRenderer.flatten(base: image, annotations: annotations)
            _ = try storage.saveEditedCapture(rendered, rawURL: rawURL)
            flattenedIsStale = false
            lastFlattenedWrite = Date()
            // Deliberately does NOT touch the pasteboard. Auto-save used to copy here too, which
            // meant every settled edit silently replaced whatever the user had copied — annotate
            // for a minute and anything you'd put on the clipboard was gone. Copying is an
            // explicit action; it belongs in `copy(annotations:)` alone.
            //
            // Persists the actual editable annotation objects (not just the flattened preview)
            // so reopening this capture later — from Recents, or after relaunching Clipr —
            // restores them instead of showing a plain, no-longer-editable image. This is what
            // makes returning to a previously-edited capture not read as "losing" the edits.
            try storage.saveAnnotations(annotations, rawURL: rawURL)
        } catch {
            NSLog("Clipr: auto-save failed: \(error)")
        }
    }

    /// Exports a flattened copy wherever the user chooses, in PNG or JPEG.
    ///
    /// Separate from the capture's own file: auto-save already keeps that current in the save
    /// folder, so this is for handing a copy to someone else, in a format they can use.
    private func saveAs(annotations: [AnnotationObject]) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = ExportFormat.allCases.map(\.contentType)
        panel.nameFieldStringValue = rawURL.deletingPathExtension().lastPathComponent
        panel.canCreateDirectories = true
        panel.message = "Export a copy of this capture"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            // The format follows the extension the panel settled on, so picking a type in its
            // filter or typing ".jpg" both do what the user expects.
            let format = ExportFormat.allCases.first { $0.fileExtension == url.pathExtension.lowercased() }
                ?? (url.pathExtension.lowercased() == "jpeg" ? .jpeg : .png)
            let flattened = AnnotationRenderer.flatten(base: self.image, annotations: annotations)
            do {
                try self.storage.export(flattened, to: url, format: format)
            } catch {
                NSLog("Clipr: export failed: \(error)")
                let alert = NSAlert()
                alert.messageText = "Couldn't export the image"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.beginSheetModal(for: window)
            }
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
            return true
        } catch {
            NSLog("Clipr: \(operation) failed to write \(rawURL.lastPathComponent): \(error)")
            let alert = NSAlert()
            alert.messageText = "Couldn't \(operation) this capture"
            alert.informativeText = "\(rawURL.lastPathComponent) could not be written, so it was left unchanged.\n\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
            return false
        }
    }

    /// `topLeftRect` is in top-left/y-down space (matching the corner handles in
    /// `EditorView.canvasResizeHandles`) and, unlike a plain crop rect, may extend beyond the
    /// current image's own bounds (an outward drag) or be smaller (an inward drag) — see
    /// `CaptureGeometry.resizedCanvas` for how that single operation handles both.
    private func applyCanvasResize(topLeftRect: CGRect, annotations: [AnnotationObject]) {
        let oldHeight = image.size.height
        let delta = CaptureGeometry.rendererDelta(oldHeight: oldHeight, newTopLeftOrigin: topLeftRect.origin, newSize: topLeftRect.size)
        guard let resized = CaptureGeometry.resizedCanvas(image, to: topLeftRect, delta: delta) else { return }
        guard writeBaseImage(resized, operation: "resize") else { return }
        image = resized
        let remapped = CaptureGeometry.remapAnnotations(annotations, delta: delta, newSize: topLeftRect.size)
        persist(remapped)
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
        persist(previousAnnotations)
        guard let newImage = NSImage(contentsOf: url) else { return }
        image = newImage
        rawURL = url
        window?.contentView = makeContentView()
    }

}
