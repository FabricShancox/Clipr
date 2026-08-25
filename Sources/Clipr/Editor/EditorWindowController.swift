import Cocoa
import SwiftUI

final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let image: NSImage
    private let rawURL: URL
    private let storage: StorageManager
    var onFinished: (() -> Void)?

    init(image: NSImage, rawURL: URL, storage: StorageManager) {
        self.image = image
        self.rawURL = rawURL
        self.storage = storage

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Clipr Editor"
        super.init(window: window)

        // Delegate assignment needs `self` to exist, so it happens after super.init.
        // windowWillClose(_:) is the single place onFinished fires — see finish()/discard()
        // below, which both just call close() and rely on this delegate callback (fired
        // synchronously by close(), before the window actually closes) rather than calling
        // onFinished themselves. That also covers the native title-bar close button, which
        // bypasses finish()/discard() entirely but still triggers windowWillClose(_:).
        window.delegate = self

        window.contentView = NSHostingView(rootView: EditorView(
            image: image,
            onDone: { [weak self] annotations in self?.finish(annotations: annotations) },
            onDiscard: { [weak self] in self?.discard() }
        ))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    func windowWillClose(_ notification: Notification) {
        onFinished?()
    }

    private func finish(annotations: [AnnotationObject]) {
        let flattened = AnnotationRenderer.flatten(base: image, annotations: annotations)
        do {
            _ = try storage.saveEditedCapture(flattened, rawURL: rawURL)
            storage.copyToClipboard(flattened)
        } catch {
            NSLog("Clipr: failed to save edited capture: \(error)")
        }
        close()
    }

    private func discard() {
        close()
    }
}
