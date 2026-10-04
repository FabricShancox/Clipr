import Cocoa
import UniformTypeIdentifiers

/// Opens captures and image files in the editor, and keeps the open editors alive.
///
/// NSWindow does NOT retain its NSWindowController, so a locally-created one merely shown would be
/// deallocated immediately. Each editor is kept here until it signals it's done;
/// `AdvancedModeCoordinator` does the same internally for its Review windows.
@MainActor
final class EditorPresenter {
    private let storage: StorageManager
    private let settings: SettingsStore
    private(set) var openEditors: [EditorWindowController] = []

    init(storage: StorageManager, settings: SettingsStore) {
        self.storage = storage
        self.settings = settings
    }

    var windows: [NSWindow?] { openEditors.map { $0.window } }

    /// Shows a capture in the editor, reusing an already-open window rather than adding another.
    ///
    /// Every capture used to build its own `EditorWindowController`, so a run of screenshots left
    /// a stack of windows on screen — each pinned to the full visible frame and holding its own
    /// full-resolution image — with no guarantee the newest was the one in front. Reuse matches
    /// what clicking a Recents thumbnail already does: the capture is swapped into the window in
    /// place. A second editor only appears if the user closed the last one.
    func openEditor(image: NSImage, rawURL: URL) {
        if let existing = frontmostEditor() {
            existing.present(image: image, rawURL: rawURL)
            return
        }
        let editor = EditorWindowController(image: image, rawURL: rawURL, storage: storage, settings: settings)
        openEditors.append(editor)
        editor.onFinished = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.openEditors.removeAll { $0 === editor }
        }
        editor.showWindow(nil)
    }

    /// The open editor nearest the front, so a capture lands in the window the user was last
    /// looking at rather than in whichever one happens to be oldest. `NSApp.orderedWindows` is
    /// front-to-back; the fallback covers an editor that's currently miniaturized, and so absent
    /// from that ordering.
    func frontmostEditor() -> EditorWindowController? {
        for window in NSApp.orderedWindows {
            if let editor = openEditors.first(where: { $0.window === window }) { return editor }
        }
        return openEditors.last
    }

    /// Opens the editor on an existing image file instead of a fresh capture.
    ///
    /// The picked file is NOT edited in place: crop and canvas-resize rewrite the editor's raw
    /// file, which used to destroy the user's original (and give a JPEG PNG bytes under its old
    /// name). Unless it's already a PNG in the capture folder, it's imported there as a new PNG
    /// first — see `StorageManager.importForEditing` — and the original is never written to.
    func openImage() {
        let panel = Panels.chooseFile(title: "Open Image in Clipr", types: [.png, .jpeg, .tiff, .bmp, .gif, .heic])
        // Chosen from the status menu while another app is frontmost: without activating, the
        // panel (and any alert after it) can open behind that app.
        WindowPresenter.activateApp()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let image: NSImage
        switch DecodeLimits.loadImage(at: url) {
        case .loaded(let loaded):
            image = loaded
        case .unreadable:
            showOpenImageFailure(url, reason: "It isn't an image Clipr can read.")
            return
        case .tooLarge(let width, let height):
            showOpenImageFailure(url, reason: "It is \(width) × \(height) pixels, which is too large to edit.")
            return
        }
        do {
            let editable = try storage.importForEditing(url, image: image)
            openEditor(image: image, rawURL: editable)
        } catch {
            NSLog("Clipr: could not import \(url.lastPathComponent): \(error)")
            Alerts.run("Couldn't open this image", "Clipr couldn't copy \(url.lastPathComponent) into your capture folder, so it wasn't opened. The original wasn't changed.\n\n\(error.localizedDescription)")
        }
    }

    /// Quitting abandons every editor's pending 800ms auto-save debounce, so the last edit in each
    /// open window would be lost silently. This writes them synchronously.
    func flushPendingSaves() {
        for editor in openEditors {
            editor.flushPendingSave()
        }
    }

    private func showOpenImageFailure(_ url: URL, reason: String) {
        Alerts.run("Couldn't open \(url.lastPathComponent)", reason)
    }
}
