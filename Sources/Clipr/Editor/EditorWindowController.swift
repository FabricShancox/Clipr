import Cocoa
import SwiftUI

final class EditorWindowController: NSWindowController {
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

        window.contentView = NSHostingView(rootView: EditorView(
            image: image,
            onDone: { [weak self] annotations in self?.finish(annotations: annotations) },
            onDiscard: { [weak self] in self?.discard() }
        ))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func finish(annotations: [AnnotationObject]) {
        let flattened = AnnotationRenderer.flatten(base: image, annotations: annotations)
        do {
            _ = try storage.saveEditedCapture(flattened, rawURL: rawURL)
            storage.copyToClipboard(flattened)
        } catch {
            NSLog("Clipr: failed to save edited capture: \(error)")
        }
        close()
        onFinished?()
    }

    private func discard() {
        close()
        onFinished?()
    }
}
