import Cocoa
import SwiftUI
import UniformTypeIdentifiers

final class ReviewWindowController: NSWindowController, NSWindowDelegate {
    private let storage: StorageManager
    private let settings: SettingsStore
    /// Set once the window exists; owns the export sheets and the running export.
    private var exportFlow: ExportFlowController?
    private let model: ReviewModel
    private let captureReplacement: (@escaping (NSImage?) -> Void) -> Void
    let sessionFolder: URL
    /// The session's open image editors, each paired with the step it edits so that step's image
    /// can't be replaced while the editor still holds the old one. Shared with any later Review of
    /// the same session (see `SessionEditorRegistry`), so it outlives this window.
    private let editors: SessionEditorRegistry
    var windowID: CGWindowID? { window.map { CGWindowID($0.windowNumber) } }

    @MainActor
    init(sessionFolder: URL, storage: StorageManager, settings: SettingsStore = SettingsStore(),
         editors: SessionEditorRegistry = SessionEditorRegistry(),
         captureReplacement: @escaping (@escaping (NSImage?) -> Void) -> Void) {
        self.storage = storage
        self.editors = editors
        self.settings = settings
        self.captureReplacement = captureReplacement
        self.sessionFolder = sessionFolder
        model = ReviewModel(folder: sessionFolder)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Review — \(sessionFolder.lastPathComponent)"
        window.minSize = NSSize(width: 560, height: 400)
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ReviewView(
            model: model,
            onOpenEditor: { [weak self] step in self?.openEditor(for: step) },
            onRetake: { [weak self] step in self?.retake(step) },
            onReplaceWithFile: { [weak self] step in self?.replaceWithFile(step) },
            onShowInFinder: { NSWorkspace.shared.activateFileViewerSelecting([sessionFolder]) },
            onExport: { [weak self] in self?.showExport() }
        ))
        exportFlow = ExportFlowController(window: window, settings: settings)
        window.center()
        attachEditors()
    }

    /// Takes over the session's editor registry — including editors left open by an earlier Review
    /// of this session — so their steps stay locked and finishing one reloads its row here.
    @MainActor
    private func attachEditors() {
        let model = model
        model.stepsInEditor = editors.stepIDs
        editors.onStepsInEditorChanged = { ids in MainActor.assumeIsolated { model.stepsInEditor = ids } }
        editors.onEditorFinished = { stepID in
            MainActor.assumeIsolated {
                // Drop every cached decode for this step so the row shows the edited image.
                if let step = model.manifest.steps.first(where: { $0.id == stepID }) {
                    for companion in StepFiles.companions(of: step.file, in: model.folder) {
                        model.thumbnails.remove(companion)
                    }
                }
                model.reload(changedStep: stepID)
            }
        }
    }

    /// The editors stay open (and in the registry) for the next Review of this session; only
    /// this window stops listening to them.
    private func detachEditors() {
        editors.onStepsInEditorChanged = nil
        editors.onEditorFinished = nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Clipr is a menu-bar (accessory) app, so a plain `showWindow` can open the Review window
    /// behind whatever app the user was just recording — activate so it actually comes forward.
    func present() {
        WindowPresenter.bringToFront(self)
    }

    /// Saves the session's pending caption (retrying a failed save) and any edits pending in
    /// image editors opened from it — the same flush `AppDelegate` gives its own editors on quit.
    func flush() {
        editors.flushAll()
        MainActor.assumeIsolated { model.flush() }
    }

    /// If the session still can't be saved after a last retry, closing would discard edits that
    /// exist only in memory, so ask first.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        flush()
        guard MainActor.assumeIsolated({ model.hasUnsavedChanges }) else { return true }
        return Alerts.run("Couldn't save your changes to this session.",
                          buttons: ["Keep Window Open", "Close Anyway"]) == .alertSecondButtonReturn
    }

    /// A caption typed in the last half-second must still be saved.
    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { model.flush() }
        detachEditors()
    }

    /// Exports what Review shows now: a caption typed in the last half-second, and annotations
    /// still inside an open editor's auto-save delay, are saved first, so the guide has them.
    /// Read-only sessions export too — exporting never writes to the session.
    private func showExport() {
        flush()
        MainActor.assumeIsolated {
            exportFlow?.begin(manifest: model.manifest, folder: model.folder, selection: model.selection)
        }
    }

    /// The capture overlay hides Clipr's windows (this one included) while it's up and restores
    /// them afterwards, so the user can capture whatever was behind Review.
    private func retake(_ step: StepRecord) {
        captureReplacement { [weak self] image in
            guard let self else { return }
            if let image { MainActor.assumeIsolated { self.model.replaceImage(for: step.id, with: image) } }
            self.present()
        }
    }

    private func replaceWithFile(_ step: StepRecord) {
        let panel = Panels.chooseFile(title: "Replace Image", prompt: "Replace", types: [.png, .jpeg, .heic, .tiff])
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let model = self.model
            // A large photo takes a noticeable time to decode and re-encode; doing it here would
            // freeze the window. The model applies the result back on the main actor.
            Task.detached(priority: .userInitiated) {
                let png = StepFiles.replacementPNG(from: url)
                await MainActor.run {
                    guard let png else { return model.showBanner("Couldn't open \(url.lastPathComponent)") }
                    model.replaceImage(for: step.id, withPNG: png)
                }
            }
        }
    }

    /// One editor per step: a second would load the same sidecar and each would save over the
    /// other's annotations. Asking again brings the open one forward.
    private func openEditor(for step: StepRecord) {
        if let open = editors.entry(for: step.id) {
            open.bringForward()
            return
        }
        let url = model.url(for: step)
        // Checked from the header first: a session folder from elsewhere could hold a tiny PNG
        // that declares billions of pixels.
        guard UntrustedImageLimits.isSafeToDecode(url),
              !UntrustedImageLimits.sidecarTooLarge(forRaw: url) else {
            MainActor.assumeIsolated { model.showBanner("\(step.file) is too large to open") }
            return
        }
        guard let image = NSImage(contentsOf: url) else { return }
        // Rename disabled: session.json refers to steps by filename.
        let editor = EditorWindowController(image: image, rawURL: url, storage: storage, allowsRename: false)
        let registry = editors
        editor.onFinished = { [weak registry, weak editor] in
            guard let registry, let editor else { return }
            registry.finished(editor)
        }
        registry.add(.init(
            editor: editor, stepID: step.id,
            flush: { [weak editor] in editor?.flushPendingSave() },
            bringForward: { [weak editor] in if let editor { WindowPresenter.bringToFront(editor) } }
        ))
        editor.showWindow(nil)
    }
}
