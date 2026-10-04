import Cocoa
import SwiftUI

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    // Internal rather than private where the `EditorWindowController+…` extensions need them;
    // nothing outside the controller and its extensions uses them.
    var image: NSImage
    var rawURL: URL
    let storage: StorageManager
    let settings: SettingsStore
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
    var latestHistory = EditorHistory()

    /// Bumped on every content-view swap (crop, canvas-resize, rename, opening another capture).
    /// A debounced save carries the generation it was scheduled under, so one left in flight from
    /// a view that has since been replaced can be told apart from a current one. Comparing URLs
    /// alone is not enough: crop and canvas-resize keep the same `rawURL`, so a pre-crop debounce
    /// would otherwise pass the URL check and overwrite the correctly-remapped save with
    /// annotations still in pre-crop coordinates.
    var generation = 0

    /// Whether `_edited.png` no longer reflects the current annotations, so a write is worth doing.
    var flattenedIsStale = false
    var lastFlattenedWrite = Date.distantPast
    /// Minimum gap between flattened writes while the user is actively editing. Re-encoding a
    /// full-screen Retina capture costs ~250ms on the main thread (measured: 11ms at 1280x800,
    /// 77ms at 3420x2146, 248ms at 6000x4000) and the debounce fires every 800ms, so writing it on
    /// every settled edit made the editor hitch continuously on large captures.
    static let flattenedWriteInterval: TimeInterval = 3

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
    /// `EditorPresenter.flushPendingSaves` on quit.
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
    /// JSON sidecar (`StorageManager.readAnnotations`) — empty for a capture that's never been
    /// edited, or the exact set restored for one that has. `applyCrop`/`applyCanvasResize` pass
    /// an explicit (already-remapped) array instead, since loading from disk there would fetch
    /// the pre-crop/resize geometry.
    func makeContentView(
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

    /// Shows an already-loaded image (a fresh capture, or a file picked via Open) in THIS window
    /// instead of opening another one.
    ///
    /// `EditorPresenter` routes every capture through here when an editor is already open: taking ten
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
