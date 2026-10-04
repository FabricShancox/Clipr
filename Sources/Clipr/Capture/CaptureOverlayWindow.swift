import Cocoa
import SwiftUI

/// The full-screen overlay, one per display, that the user drags or clicks on to choose a capture.
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

    // Clipr's own ordinary windows, ordered out for the duration of a capture and put back by
    // `restoreHiddenWindows`. See `hideOwnWindows` for why.
    private static var hiddenWindows: [NSWindow] = []

    /// `frozenScreens` are the stills `CaptureManager` took before calling this, drawn under each
    /// overlay so the user selects from exactly what will be captured — see
    /// `CaptureManager.frozenScreens`.
    static func showAll(frozenScreens: [CGDirectDisplayID: NSImage], onResult: @escaping (CaptureResult) -> Void) {
        dismissAll()
        // The overlay that gets key (and main) status: the one on the screen the pointer is
        // already on, since that's where the user is about to drag. Which window holds those two
        // roles decides what activation below is allowed to raise, so it has to be settled before
        // the app is activated rather than left to whichever screen happened to come last.
        hideOwnWindows()
        let mouseLocation = NSEvent.mouseLocation
        var primary: CaptureOverlayWindow?
        for screen in NSScreen.screens {
            let window = makeOverlay(for: screen, frozenImage: frozenScreens[screen.displayID], onResult: onResult)
            // Ordered front WITHOUT claiming key here: `makeKeyAndOrderFront` on every screen's
            // overlay left the last one made key by accident, and made the key window change
            // once per screen on the way there.
            window.orderFrontRegardless()
            openWindows.append(window)
            if screen.frame.contains(mouseLocation) { primary = window }
        }
        (primary ?? openWindows.first)?.makeKeyAndOrderFront(nil)

        // NOT `NSApp.activate(ignoringOtherApps: true)`, which brings EVERY window of the app
        // forward. An editor left open from an earlier capture was therefore yanked in front of
        // whatever the user was about to shoot the moment the hotkey fired — clearly visible
        // through the 15%-opacity overlay, taking focus, and then baked into the captured image,
        // since the display filter in `CaptureManager` excluded nothing back then. It only happened
        // "sometimes" because it needs an editor window to already be open and positioned over
        // the area being captured.
        //
        // Activating through `NSRunningApplication` without `.activateAllWindows` brings only the
        // key and main windows forward, and the overlay claimed both just above (hence
        // `canBecomeMain` below — a borderless window refuses main status by default, which would
        // have left the editor as main and raised it anyway). No `.activateIgnoringOtherApps`:
        // it's deprecated as of macOS 14 (this app's minimum) and documented as having no effect.
        NSRunningApplication.current.activate(options: [])
        if !isCrosshairPushed {
            NSCursor.crosshair.push()
            isCrosshairPushed = true
        }
    }

    /// One screen's borderless overlay, hosting a `CaptureOverlayView`. Not yet on screen.
    private static func makeOverlay(for screen: NSScreen, frozenImage: NSImage?,
                                    onResult: @escaping (CaptureResult) -> Void) -> CaptureOverlayWindow {
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
        // Belt-and-suspenders: on mixed-DPI multi-monitor setups (e.g. a 2x main display
        // alongside 1x externals), the `contentRect`/`screen:` given to this initializer has
        // been observed to leave borderless windows mispositioned/mis-sized on non-main
        // displays (verified live on a 3-monitor 2x+1x+1x rig: correct on the main screen,
        // partially or fully off-screen on the others). Forcing the frame explicitly after
        // construction is the standard, more reliable way to pin a window to a specific
        // screen's exact bounds regardless of that initial placement quirk.
        window.setFrame(screen.frame, display: true)
        window.onResult = onResult
        window.contentView = NSHostingView(rootView: CaptureOverlayView(screen: screen, frozenImage: frozenImage, onResult: { result in
            dismissAll()
            onResult(result)
        }))
        return window
    }

    /// Takes Clipr's own windows off screen before the overlay goes up.
    ///
    /// The editor opens at the screen's full visible frame, and a capture now reuses it rather
    /// than stacking up new ones, so by the second screenshot it is typically the frontmost thing
    /// on the display — meaning the hotkey put the editor, not the user's actual screen, inside
    /// the selection. The display filter in `CaptureManager` excluded nothing then, so it was captured
    /// verbatim. Ordering these out is also what Advanced Mode already does in spirit (see
    /// `windowIDs(of:)`): Clipr never appears in its own captures.
    ///
    /// Restricted to `.normal`-level windows, which leaves the status item's own window (at
    /// `.statusBar`) alone — hiding that would blank the menu bar icon mid-capture.
    private static func hideOwnWindows() {
        hiddenWindows = NSApp.windows.filter { window in
            window.isVisible && window.level == .normal && !(window is CaptureOverlayWindow)
        }
        hiddenWindows.forEach { $0.orderOut(nil) }
    }

    /// Puts back whatever `hideOwnWindows` took off screen. Called by `CaptureManager` once the
    /// screenshot has actually been taken — NOT from `dismissAll`, which runs while the capture is
    /// still pending and would let the editor back on screen in time to appear in it.
    static func restoreHiddenWindows() {
        hiddenWindows.forEach { $0.orderFront(nil) }
        hiddenWindows = []
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

    /// Borderless windows are not main-window candidates by default. Without this the app's
    /// editor window stays `mainWindow` and activation raises it over the capture — see `showAll`.
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        let callback = onResult
        CaptureOverlayWindow.dismissAll()
        callback?(.cancelled)
    }
}
