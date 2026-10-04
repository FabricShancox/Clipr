import Cocoa
import ScreenCaptureKit

final class CaptureManager {
    private let storage: StorageManager
    var onCaptureFinished: ((URL, NSImage) -> Void)?
    /// Fired on the main actor when a capture the user asked for didn't produce anything.
    ///
    /// Failures used to be logged and nothing else, so the most visible case — Screen Recording
    /// revoked in System Settings after launch, where the cached permission check still passes and
    /// the overlay still appears — ended with the drag completing and simply nothing happening.
    var onCaptureFailed: ((Error) -> Void)?
    /// Whether the mouse cursor should be baked into captured images. Off by default (see
    /// `SettingsStore.captureCursor`) — `AppDelegate` keeps this in sync with the user's
    /// preference at launch and whenever it changes in Preferences.
    var captureCursor = false

    /// Each display as it looked the instant the hotkey fired, keyed by display ID.
    ///
    /// Area and full-screen captures are cropped from these rather than shot live once the
    /// selection is done. Bringing the overlay up activates Clipr, which deactivates the app the
    /// user is shooting — and macOS closes an app's open menus, pop-up buttons and dropdowns the
    /// moment it deactivates (a click on the overlay would dismiss them too). A live capture after
    /// the drag therefore never contained the dropdown the user was trying to screenshot. Taken
    /// before the overlay exists, nothing has lost focus yet.
    private var frozenScreens: [CGDirectDisplayID: NSImage] = [:]

    init(storage: StorageManager) {
        self.storage = storage
    }

    /// What a capture is for. Each capture carries its own mode from the moment it starts, so a
    /// screenshot taken with the hotkey can never be handed to a Review retake, and a retake is
    /// never saved, copied or opened in the editor.
    enum CaptureMode {
        case normal
        case replacement((NSImage?) -> Void)
    }

    /// True from the moment a capture starts until its result has been handled. A second capture
    /// started meanwhile would replace the overlay and the list of windows it hid, so the first
    /// capture's windows would never come back; it is ignored instead.
    private var isCapturing = false

    /// Runs the normal capture overlay and returns the image (nil if cancelled, failed or another
    /// capture is already in progress) without saving it anywhere. Completes on the main thread.
    @MainActor
    func captureImage(completion: @escaping (NSImage?) -> Void) {
        guard PermissionsManager.hasScreenRecordingPermission() else {
            PermissionsManager.requestScreenRecordingPermission()
            completion(nil)
            return
        }
        beginCapture(mode: .replacement(completion))
    }

    /// Main thread only (it guards on, and sets, `isCapturing`).
    @MainActor
    func beginCapture(mode: CaptureMode = .normal) {
        guard !isCapturing else {
            if case .replacement(let completion) = mode { completion(nil) }
            return
        }
        guard PermissionsManager.hasScreenRecordingPermission() else {
            PermissionsManager.requestScreenRecordingPermission()
            if case .replacement(let completion) = mode { completion(nil) }
            return
        }
        isCapturing = true
        Task { @MainActor in
            do {
                frozenScreens = try await Self.snapshotScreens(NSScreen.screens, showsCursor: captureCursor)
            } catch {
                NSLog("Clipr capture failed: \(error)")
                isCapturing = false
                onCaptureFailed?(error)
                if case .replacement(let completion) = mode { completion(nil) }
                return
            }
            CaptureOverlayWindow.showAll(frozenScreens: frozenScreens) { [weak self] result in
                self?.handle(result, mode: mode)
            }
        }
    }

    /// Hands a finished capture to whoever asked for it: a replacement gets the image (or nil)
    /// back on the main thread and nothing else happens to it; a normal capture is saved, and a
    /// cancelled one is dropped. Separate from `handle` so the routing can be tested without a
    /// screen.
    static func deliver(_ image: NSImage?, mode: CaptureMode, save: (NSImage) async throws -> Void) async rethrows {
        switch mode {
        case .replacement(let completion):
            await MainActor.run { completion(image) }
        case .normal:
            if let image { try await save(image) }
        }
    }

    private func handle(_ result: CaptureResult, mode: CaptureMode) {
        Task {
            do {
                let image: NSImage?
                switch result {
                case .area(let rect, let screen):
                    image = try Self.crop(try await frozenImage(of: screen), to: rect, scale: screen.backingScaleFactor)
                case .fullScreen(let screen):
                    image = try await frozenImage(of: screen)
                case .window(let windowInfo):
                    // Still live: a window capture is of that one window with its own
                    // transparency, which a crop of the frozen display can't reproduce.
                    image = try await Self.captureWindow(windowInfo, showsCursor: captureCursor)
                case .cancelled:
                    image = nil
                }
                // The screenshot has been taken, so Clipr's own windows can come back — see
                // `CaptureOverlayWindow.hideOwnWindows`. Before delivering, so a cancelled
                // capture puts them back too rather than leaving the editor hidden for good.
                await MainActor.run {
                    CaptureOverlayWindow.restoreHiddenWindows()
                    frozenScreens = [:]
                    isCapturing = false
                }
                try await Self.deliver(image, mode: mode) { image in
                    let rawURL = try storage.saveRawCapture(image, date: Date())
                    storage.copyToClipboard(image)
                    await MainActor.run { onCaptureFinished?(rawURL, image) }
                }
            } catch {
                NSLog("Clipr capture failed: \(error)")
                await MainActor.run {
                    CaptureOverlayWindow.restoreHiddenWindows()
                    frozenScreens = [:]
                    isCapturing = false
                    onCaptureFailed?(error)
                }
                await Self.deliver(nil, mode: mode, save: { _ in })
            }
        }
    }

    /// The frozen still of `screen`, or a live shot if it has none (a display plugged in
    /// mid-capture).
    @MainActor
    private func frozenImage(of screen: NSScreen) async throws -> NSImage {
        if let frozen = frozenScreens[screen.displayID] { return frozen }
        return try await Self.captureFullScreen(screen, showsCursor: captureCursor)
    }

    static func snapshotScreens(_ screens: [NSScreen], showsCursor: Bool) async throws -> [CGDirectDisplayID: NSImage] {
        var snapshots: [CGDirectDisplayID: NSImage] = [:]
        for screen in screens {
            snapshots[screen.displayID] = try await captureFullScreen(screen, showsCursor: showsCursor)
        }
        return snapshots
    }

    static func captureFullScreen(_ screen: NSScreen, showsCursor: Bool) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        // Clipr's own ordinary windows (an editor left open) are left out, as they never belong in
        // a capture. Only `.normal`-layer ones, so the menu bar icon still appears.
        let ownWindows = content.windows.filter {
            $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier && $0.windowLayer == 0
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let config = SCStreamConfiguration()
        config.showsCursor = showsCursor
        // `SCDisplay.width`/`.height` are documented (ScreenCaptureKit/SCShareableContent.h) as the
        // display's width/height in POINTS, whereas `SCStreamConfiguration.width`/`.height`
        // (ScreenCaptureKit/SCStream.h) are the output width/height in PIXELS. Assigning the former
        // straight into the latter would request a point-sized pixel buffer - i.e. a half-resolution
        // capture on any 2x Retina display - and would also leave the returned `CGImage` smaller
        // than `crop` below assumes when it scales its crop rect into pixel space. Convert
        // points -> pixels explicitly with the screen's backing scale factor, matching what
        // `captureWindow` already does for its (also points-based) `kCGWindowBounds` size.
        let scale = screen.backingScaleFactor
        config.width = Int((CGFloat(display.width) * scale).rounded())
        config.height = Int((CGFloat(display.height) * scale).rounded())
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        // Point-sized, every pixel kept — see `NSImage+PixelScale.swift`.
        return NSImage(bitmap: cgImage, scale: scale)
    }

    private static func crop(_ fullImage: NSImage, to rect: CGRect, scale: CGFloat) throws -> NSImage {
        guard let cgImage = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureError.cropFailed
        }
        // `rect` arrives from CaptureOverlayView in the overlay's VIEW-LOCAL POINTS space (the
        // overlay view fills `screen.frame`, which is in points, and the rect comes straight from
        // a SwiftUI DragGesture). `cgImage` above, however, was captured at the display's native
        // PIXEL resolution: `SCDisplay.width`/`.height` are themselves in points, so
        // `captureFullScreen` (which took the frozen still) explicitly multiplies them by `screen.backingScaleFactor` before
        // assigning them to `SCStreamConfiguration.width`/`.height` (which are documented in
        // pixels) - meaning the `CGImage` handed back here genuinely is pixel-sized. On any
        // Retina display (backingScaleFactor > 1) those two spaces differ, so the points-space rect
        // must be scaled up to pixel space before it can be used to crop the pixel-space image, or
        // the crop comes out the wrong size and in the wrong position. Example: on a 2x Retina
        // screen, a rect selected at points (100, 100, 200, 150) must crop pixels
        // (200, 200, 400, 300) - exactly 2x every component (origin and size alike).
        let pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        guard let cropped = cgImage.cropping(to: pixelRect) else {
            throw CaptureError.cropFailed
        }
        return NSImage(bitmap: cropped, scale: scale)
    }

    static func captureWindow(_ windowInfo: WindowInfo, showsCursor: Bool) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scWindow = content.windows.first(where: { $0.windowID == windowInfo.windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        config.showsCursor = showsCursor
        // `windowInfo.bounds` (from `kCGWindowBounds`, via `WindowPicker.onScreenWindows()`) is in
        // points, not native pixels. Using it directly for `SCStreamConfiguration.width`/`.height`
        // would request ScreenCaptureKit output at a lower-than-native resolution on any Retina
        // display (backingScaleFactor > 1) - the whole window still gets captured, just blurrier
        // than native. Scale by the backing scale factor of whichever screen actually contains the
        // window, so the requested output resolution matches the window's real pixel density.
        let scale = screenScaleFactor(containing: windowInfo.bounds.origin)
        config.width = Int((windowInfo.bounds.width * scale).rounded())
        config.height = Int((windowInfo.bounds.height * scale).rounded())
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(bitmap: cgImage, scale: scale)
    }
}
