import Cocoa
import SwiftUI
import UniformTypeIdentifiers

final class ReviewWindowController: NSWindowController, NSWindowDelegate {
    private let storage: StorageManager
    private let model: ReviewModel
    private let captureReplacement: (@escaping (NSImage?) -> Void) -> Void
    let sessionFolder: URL
    // Keeps each opened EditorWindowController alive until it finishes; without this,
    // the local `editor` in openEditor(for:) would be deallocated as soon as that
    // function returns, silently breaking its Done/Discard closures (which capture
    // `[weak self]` on the editor controller). Each is paired with the step it edits, so that
    // step's image can't be replaced while the editor still holds the old one.
    private var openEditors: [(editor: EditorWindowController, stepID: UUID)] = []
    var windowID: CGWindowID? { window.map { CGWindowID($0.windowNumber) } }

    @MainActor
    init(sessionFolder: URL, storage: StorageManager, captureReplacement: @escaping (@escaping (NSImage?) -> Void) -> Void) {
        self.storage = storage
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
            onShowInFinder: { NSWorkspace.shared.activateFileViewerSelecting([sessionFolder]) }
        ))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Clipr is a menu-bar (accessory) app, so a plain `showWindow` can open the Review window
    /// behind whatever app the user was just recording — activate so it actually comes forward.
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Saves the session's pending caption (retrying a failed save) and any edits pending in
    /// image editors opened from it — the same flush `AppDelegate` gives its own editors on quit.
    func flush() {
        for open in openEditors { open.editor.flushPendingSave() }
        MainActor.assumeIsolated { model.flush() }
    }

    /// If the session still can't be saved after a last retry, closing would discard edits that
    /// exist only in memory, so ask first.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        flush()
        guard MainActor.assumeIsolated({ model.hasUnsavedChanges }) else { return true }
        let alert = NSAlert()
        alert.messageText = "Couldn't save your changes to this session."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Window Open")
        alert.addButton(withTitle: "Close Anyway")
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// A caption typed in the last half-second must still be saved.
    func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { model.flush() }
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
        let panel = NSOpenPanel()
        panel.title = "Replace Image"
        panel.prompt = "Replace"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
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

    private func openEditor(for step: StepRecord) {
        let url = model.url(for: step)
        guard let image = NSImage(contentsOf: url) else { return }
        // Rename disabled: session.json refers to steps by filename.
        let editor = EditorWindowController(image: image, rawURL: url, storage: storage, allowsRename: false)
        openEditors.append((editor, step.id))
        updateStepsInEditor()
        editor.onFinished = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.openEditors.removeAll { $0.editor === editor }
            self.updateStepsInEditor()
            MainActor.assumeIsolated {
                let folder = self.model.folder
                // Drop every cached decode for this step so the row shows the edited image.
                for companion in StepFiles.companions(of: step.file, in: folder) {
                    ThumbnailCache.shared.remove(companion)
                }
                self.model.reload()
            }
        }
        editor.showWindow(nil)
    }

    private func updateStepsInEditor() {
        let ids = Set(openEditors.map(\.stepID))
        MainActor.assumeIsolated { model.stepsInEditor = ids }
    }
}
