import Cocoa
import SwiftUI

final class CaptureOverlayWindow: NSWindow {
    private static var openWindows: [CaptureOverlayWindow] = []

    // Stashed so cancelOperation (Escape) can report `.cancelled` back to the caller; the enum
    // case exists specifically for this, but nothing else in the flow ever produces it.
    private var onResult: ((CaptureResult) -> Void)?

    static func showAll(onResult: @escaping (CaptureResult) -> Void) {
        dismissAll()
        for screen in NSScreen.screens {
            let window = CaptureOverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.onResult = onResult
            window.contentView = NSHostingView(rootView: CaptureOverlayView(screen: screen, onResult: { result in
                dismissAll()
                onResult(result)
            }))
            window.makeKeyAndOrderFront(nil)
            openWindows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    static func dismissAll() {
        openWindows.forEach { $0.orderOut(nil) }
        openWindows = []
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        let callback = onResult
        CaptureOverlayWindow.dismissAll()
        callback?(.cancelled)
    }
}
