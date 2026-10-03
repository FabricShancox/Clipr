import Cocoa
import SwiftUI

final class ReviewWindowController: NSWindowController {
    private let storage: StorageManager
    // Keeps each opened EditorWindowController alive until it finishes; without this,
    // the local `editor` in openEditor(for:) would be deallocated as soon as that
    // function returns, silently breaking its Done/Discard closures (which capture
    // `[weak self]` on the editor controller).
    private var openEditors: [EditorWindowController] = []
    var windowID: CGWindowID? { window.map { CGWindowID($0.windowNumber) } }

    init(stepURLs: [URL], sessionFolder: URL?, storage: StorageManager) {
        self.storage = storage
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = sessionFolder.map { "Review — \($0.lastPathComponent)" } ?? "Review Advanced Mode Session"
        super.init(window: window)

        window.contentView = NSHostingView(rootView: ReviewView(
            stepURLs: stepURLs,
            onOpenEditor: { [weak self] url in self?.openEditor(for: url) },
            onDelete: { url in try? FileManager.default.removeItem(at: url) },
            onShowInFinder: sessionFolder.map { folder in { NSWorkspace.shared.activateFileViewerSelecting([folder]) } }
        ))
        window.center()
    }

    /// Clipr is a menu-bar (accessory) app, so a plain `showWindow` can open the Review window
    /// behind whatever app the user was just recording — activate so it actually comes forward.
    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func openEditor(for url: URL) {
        guard let image = NSImage(contentsOf: url) else { return }
        let editor = EditorWindowController(image: image, rawURL: url, storage: storage)
        openEditors.append(editor)
        editor.onFinished = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.openEditors.removeAll { $0 === editor }
        }
        editor.showWindow(nil)
    }
}
