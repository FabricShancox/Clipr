import Cocoa
import SwiftUI

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private var image: NSImage
    private var rawURL: URL
    private let storage: StorageManager
    private let settings: SettingsStore
    private let allowsRename: Bool
    /// Shared by every content view this window shows; each one re-registers on appear.
    private let commands = EditorCommands()
    private var keyMonitor: Any?
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

    init(image: NSImage, rawURL: URL, storage: StorageManager, settings: SettingsStore = SettingsStore(), allowsRename: Bool = true) {
        self.image = image
        self.rawURL = rawURL
        self.storage = storage
        self.settings = settings
        self.allowsRename = allowsRename

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clipr Editor"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        // The editor is drawn in a fixed dark palette (`EditorColors`), which also keeps the
        // annotation swatches — white among them — legible around the canvas. Following a Light
        // system appearance put light bezels under white labels on the dark header (Reveal,
        // Save As…, the menu, the rename field, popover steppers), so the window is pinned to
        // dark; sheets and popovers attached to it inherit that.
        window.appearance = NSAppearance(named: .darkAqua)
        super.init(window: window)

        // windowWillClose(_:) is the single place onFinished fires — Copy/Share leave the
        // window open, so this only fires via the title-bar close button, Cmd+W, Esc or Return.
        window.delegate = self

        window.contentView = makeContentView()
        installKeyMonitor()
        // Opens maximized (screen's visible frame, not true fullscreen) so the capture is
        // visible at its largest size on launch — on the screen the pointer is on, which is the
        // one just captured (or where Open Image… was chosen). `NSScreen.main` is the screen of
        // whatever window was key, so the editor often opened on a different display.
        if let screen = Self.screenUnderPointer() ?? NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
        } else {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private static func screenUnderPointer() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
    }

    /// See `EditorCommands`. Only for this window, only while it has no sheet up, and never while
    /// a text view (a text annotation, the rename field) is first responder — there the keys keep
    /// their normal text meaning via the Edit menu.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window,
                  window.attachedSheet == nil,
                  !(window.firstResponder is NSText),
                  let action = EditorCommands.action(for: event),
                  let perform = self.commands.perform else { return event }
            perform(action)
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
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
        guard !persist(latestAnnotations) else { return }
        reportSaveFailureOnce()
    }

    /// Set once the user has been told this window's work couldn't be saved, so a folder that
    /// stays unwritable (a read-only volume, a revoked permission) produces one alert, not one on
    /// every focus change.
    private var hasReportedSaveFailure = false

    /// Flushes from closing, quitting or switching away used to fail with only an `NSLog`, so
    /// annotations on a capture in an unwritable folder were lost on close with no warning.
    private func reportSaveFailureOnce() {
        guard !hasReportedSaveFailure else { return }
        hasReportedSaveFailure = true
        let sheetWindow = window.flatMap { $0.isVisible && $0.attachedSheet == nil ? $0 : nil }
        Alerts.present("Couldn't save your annotations",
                       "Changes to \(rawURL.lastPathComponent) couldn't be written to its folder. Use Save As… to keep a copy elsewhere.",
                       on: sheetWindow)
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
            history: history,
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
            settingsDefaults: settings.defaults,
            onClose: { [weak self] in self?.window?.performClose(nil) },
            onSaveAs: { [weak self] annotations in self?.saveAs(annotations: annotations) },
            onRevealInFinder: { url in NSWorkspace.shared.activateFileViewerSelecting([url]) },
            onShare: { [weak self] annotations, buttonFrame in self?.share(annotations: annotations, from: buttonFrame) },
            onCropApplied: { [weak self] rendererRect, annotations in self?.applyCrop(rendererRect: rendererRect, annotations: annotations) },
            onCanvasResize: { [weak self] topLeftRect, annotations in self?.applyCanvasResize(topLeftRect: topLeftRect, annotations: annotations) },
            onDeleteCapture: { [weak self] url, deleted in self?.deleteRecent(url, then: deleted) },
            onRename: allowsRename ? { [weak self] url, newName, annotations in self?.rename(url, to: newName, annotations: annotations) } : nil,
            commands: commands
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
                let detail = backup.map {
                    "\(name) has opened without them. The unreadable file was kept as \($0.lastPathComponent) in case it can be recovered."
                } ?? "\(name) has opened without them."
                Alerts.present("Saved annotations for this capture couldn't be read", detail,
                               on: self?.window.flatMap { $0.isVisible ? $0 : nil })
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
            Alerts.present("Couldn't rename this capture",
                           "\(url.lastPathComponent) was left unchanged.\n\n\(error.localizedDescription)", on: window)
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
    /// staleness check. Failures are logged here, since this can fire often; `flushPendingSave`
    /// tells the user (once) when a flush it depends on fails.
    @discardableResult
    private func persist(_ annotations: [AnnotationObject], flattened: FlattenedWrite = .now) -> Bool {
        do {
            // The sidecar is what actually preserves the user's work — it restores editable
            // annotations on reopen and costs well under a millisecond — so it is written every
            // time. `_edited.png` is a derived export and may lag by a few seconds during active
            // editing; it is brought up to date whenever it matters (see `FlattenedWrite.now`),
            // and a stale one is regenerated from the sidecar anyway.
            try storage.saveAnnotations(annotations, rawURL: rawURL)

            let dueForWrite = flattened == .now
                || Date().timeIntervalSince(lastFlattenedWrite) >= Self.flattenedWriteInterval
            guard flattenedIsStale, dueForWrite else { return true }

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
            return true
        } catch {
            NSLog("Clipr: auto-save failed: \(error)")
            return false
        }
    }

    /// Exports a flattened copy wherever the user chooses, in PNG or JPEG.
    ///
    /// Separate from the capture's own file: auto-save already keeps that current in the save
    /// folder, so this is for handing a copy to someone else, in a format they can use.
    private func saveAs(annotations: [AnnotationObject]) {
        guard let window else { return }
        let panel = Panels.saveFile(message: "Export a copy of this capture",
                                    name: rawURL.deletingPathExtension().lastPathComponent,
                                    types: ExportFormat.allCases.map(\.contentType))
        // Snapshot the image now. The capture hotkey is global, so a new capture (or a Recent)
        // can replace `self.image` while this sheet is up; reading it at Save time exported the
        // new image with the old capture's annotations drawn on it.
        let image = self.image

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            // The format follows the extension the panel settled on, so picking a type in its
            // filter or typing ".jpg" both do what the user expects.
            let format = ExportFormat.allCases.first { $0.fileExtension == url.pathExtension.lowercased() }
                ?? (url.pathExtension.lowercased() == "jpeg" ? .jpeg : .png)
            let flattened = AnnotationRenderer.flatten(base: image, annotations: annotations)
            do {
                try self.storage.export(flattened, to: url, format: format)
            } catch {
                NSLog("Clipr: export failed: \(error)")
                Alerts.present("Couldn't export the image", error.localizedDescription, on: window)
            }
        }
    }

    /// Confirms, then moves a Recent capture (and its edited copy and annotations) to the Trash.
    /// The × on a thumbnail is small and sits on every tile, so one mis-click used to delete a
    /// capture permanently with no warning; a failure was swallowed and the tile hidden anyway.
    private func deleteRecent(_ url: URL, then deleted: @escaping () -> Void) {
        guard let window else { return }
        Alerts.present("Move “\(url.lastPathComponent)” to the Trash?",
                       "Its edited copy and annotations go too. You can put them back from the Trash in Finder.",
                       buttons: ["Move to Trash", "Cancel"], on: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            do {
                try self.storage.deleteCapture(rawURL: url)
                ThumbnailCache.shared.remove(url)
                deleted()
            } catch {
                NSLog("Clipr: couldn't move \(url.lastPathComponent) to the Trash: \(error)")
                Alerts.present("Couldn't move this capture to the Trash",
                               "\(url.lastPathComponent) was left where it is.\n\n\(error.localizedDescription)", on: window)
            }
        }
    }

    private func copy(annotations: [AnnotationObject]) {
        let flattened = AnnotationRenderer.flatten(base: image, annotations: annotations)
        storage.copyToClipboard(AnnotationRenderer.applying(settings.copyStyle, to: flattened))
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

    /// `buttonFrame` is in SwiftUI's global (top-left origin) space for the hosting view; the
    /// picker is anchored to it so it pops from the Share button, not the window's corner.
    private func share(annotations: [AnnotationObject], from buttonFrame: CGRect) {
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

    /// Shows an already-loaded image (a fresh capture, or a file picked via Open) in THIS window
    /// instead of opening another one.
    ///
    /// `AppDelegate` routes every capture through here when an editor is already open: taking ten
    /// screenshots used to leave ten editor windows stacked on screen, each holding its own copy
    /// of a full-resolution image, and the newest one wasn't necessarily the one in front. The
    /// outgoing capture's annotations are flushed against the OLD `rawURL` first — same reason as
    /// `loadCapture` — so an edit still inside its 800ms debounce isn't dropped by the reassignment
    /// below. Rebuilding the content view also re-reads Recents, so the capture just replaced
    /// shows up in the sidebar.
    func present(image newImage: NSImage, rawURL url: URL) {
        persist(latestAnnotations)
        image = newImage
        rawURL = url
        window?.contentView = makeContentView()
        window?.deminiaturize(nil)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Loads a different capture into THIS window (replacing image/rawURL and rebuilding the
    /// content view) rather than opening a second editor window — clicking a "Recent" thumbnail
    /// browses in place. The incoming capture's own annotations, if any, are restored from its
    /// JSON sidecar by `makeContentView`'s default. `previousAnnotations` — the outgoing view's
    /// current annotations — are flushed synchronously against the OLD `rawURL` first, before
    /// it's reassigned, so a very recent edit that hadn't reached its debounce yet isn't lost.
    private func loadCapture(_ url: URL, previousAnnotations: [AnnotationObject]) {
        persist(previousAnnotations)
        // Header-checked before the full decode — see `DecodeLimits`.
        guard case .loaded(let newImage) = DecodeLimits.loadImage(at: url) else {
            NSSound.beep()
            return
        }
        image = newImage
        rawURL = url
        window?.contentView = makeContentView()
    }

}
