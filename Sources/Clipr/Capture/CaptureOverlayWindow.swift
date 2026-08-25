import Cocoa
import SwiftUI

final class CaptureOverlayWindow: NSWindow {
    private static var openWindows: [CaptureOverlayWindow] = []

    // Tracks whether we currently have a crosshair pushed onto NSCursor's stack, so push/pop stay
    // balanced regardless of how many times showAll/dismissAll are called or in what order.
    //
    // Deliberately NOT done via CaptureOverlayView's onAppear/onDisappear: verified by manual run
    // that SwiftUI's onDisappear does not fire when the hosting NSWindow is merely orderOut() (as
    // dismissAll does) rather than closed/removed from the view hierarchy, which would have left
    // the crosshair cursor stuck on screen after every capture. Managing the cursor at this
    // window-lifecycle level (the one place that reliably fires exactly once per show/dismiss) is
    // the fix that was verified to work.
    private static var isCrosshairPushed = false

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
        if !isCrosshairPushed {
            NSCursor.crosshair.push()
            isCrosshairPushed = true
        }
    }

    static func dismissAll() {
        openWindows.forEach { $0.orderOut(nil) }
        openWindows = []
        if isCrosshairPushed {
            NSCursor.pop()
            isCrosshairPushed = false
        }
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        let callback = onResult
        CaptureOverlayWindow.dismissAll()
        callback?(.cancelled)
    }
}
