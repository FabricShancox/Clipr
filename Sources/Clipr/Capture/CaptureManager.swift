import Cocoa
import ScreenCaptureKit

final class CaptureManager {
    private let storage: StorageManager
    var onCaptureFinished: ((URL, NSImage) -> Void)?
    /// Whether the mouse cursor should be baked into captured images. Off by default (see
    /// `SettingsStore.captureCursor`) — `AppDelegate` keeps this in sync with the user's
    /// preference at launch and whenever it changes in Preferences.
    var captureCursor = false

    init(storage: StorageManager) {
        self.storage = storage
    }

    func beginCapture() {
        guard PermissionsManager.hasScreenRecordingPermission() else {
            PermissionsManager.requestScreenRecordingPermission()
            return
        }
        CaptureOverlayWindow.showAll { [weak self] result in
            self?.handle(result)
        }
    }

    private func handle(_ result: CaptureResult) {
        Task {
            do {
                let image: NSImage?
                switch result {
                case .area(let rect, let screen):
                    image = try await Self.captureArea(rect, on: screen, showsCursor: captureCursor)
                case .fullScreen(let screen):
                    image = try await Self.captureFullScreen(screen, showsCursor: captureCursor)
                case .window(let windowInfo):
                    image = try await Self.captureWindow(windowInfo, showsCursor: captureCursor)
                case .cancelled:
                    image = nil
                }
                guard let image else { return }
                let date = Date()
                let rawURL = try storage.saveRawCapture(image, date: date)
                storage.copyToClipboard(image)
                await MainActor.run {
                    onCaptureFinished?(rawURL, image)
                }
            } catch {
                NSLog("Clipr capture failed: \(error)")
            }
        }
    }

    private static func captureFullScreen(_ screen: NSScreen, showsCursor: Bool) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.showsCursor = showsCursor
        // `SCDisplay.width`/`.height` are documented (ScreenCaptureKit/SCShareableContent.h) as the
        // display's width/height in POINTS, whereas `SCStreamConfiguration.width`/`.height`
        // (ScreenCaptureKit/SCStream.h) are the output width/height in PIXELS. Assigning the former
        // straight into the latter would request a point-sized pixel buffer - i.e. a half-resolution
        // capture on any 2x Retina display - and would also leave the returned `CGImage` smaller
        // than `captureArea` below assumes when it scales its crop rect into pixel space. Convert
        // points -> pixels explicitly with the screen's backing scale factor, matching what
        // `captureWindow` already does for its (also points-based) `kCGWindowBounds` size.
        let scale = screen.backingScaleFactor
        config.width = Int((CGFloat(display.width) * scale).rounded())
        config.height = Int((CGFloat(display.height) * scale).rounded())
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func captureArea(_ rect: CGRect, on screen: NSScreen, showsCursor: Bool) async throws -> NSImage {
        let fullImage = try await captureFullScreen(screen, showsCursor: showsCursor)
        guard let cgImage = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureError.cropFailed
        }
        // `rect` arrives from CaptureOverlayView in the overlay's VIEW-LOCAL POINTS space (the
        // overlay view fills `screen.frame`, which is in points, and the rect comes straight from
        // a SwiftUI DragGesture). `cgImage` above, however, was captured at the display's native
        // PIXEL resolution: `SCDisplay.width`/`.height` are themselves in points, so
        // `captureFullScreen` explicitly multiplies them by `screen.backingScaleFactor` before
        // assigning them to `SCStreamConfiguration.width`/`.height` (which are documented in
        // pixels) - meaning the `CGImage` handed back here genuinely is pixel-sized. On any
        // Retina display (backingScaleFactor > 1) those two spaces differ, so the points-space rect
        // must be scaled up to pixel space before it can be used to crop the pixel-space image, or
        // the crop comes out the wrong size and in the wrong position. Example: on a 2x Retina
        // screen, a rect selected at points (100, 100, 200, 150) must crop pixels
        // (200, 200, 400, 300) - exactly 2x every component (origin and size alike).
        let scale = screen.backingScaleFactor
        let pixelRect = CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        guard let cropped = cgImage.cropping(to: pixelRect) else {
            throw CaptureError.cropFailed
        }
        return NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
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
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// `windowInfo.bounds` lives in the CG "global display" points space that
    /// `CaptureOverlayView.globalDisplayPoint`/`viewLocalPoint` document and convert to/from
    /// (origin at the top-left of the main display, y increasing downward) - the same space
    /// `kCGWindowBounds` uses. To find the `backingScaleFactor` of the screen a window is actually
    /// on, each candidate `NSScreen`'s frame is converted into that same space (by reusing
    /// `CaptureOverlayView.globalDisplayPoint` on that screen's own local origin, `.zero`, which
    /// yields the screen's top-left corner in global-display coordinates) and tested for
    /// containment against the window's origin, rather than comparing `windowInfo.bounds` directly
    /// against `NSScreen.frame` (a different, Cocoa-native, bottom-left-origin/y-up space).
    private static func screenScaleFactor(containing globalDisplayPoint: CGPoint) -> CGFloat {
        for screen in NSScreen.screens {
            let topLeft = CaptureOverlayView.globalDisplayPoint(forViewLocalPoint: .zero, on: screen)
            let screenRectInGlobalDisplaySpace = CGRect(origin: topLeft, size: screen.frame.size)
            if screenRectInGlobalDisplaySpace.contains(globalDisplayPoint) {
                return screen.backingScaleFactor
            }
        }
        return NSScreen.main?.backingScaleFactor ?? 1.0
    }
}

enum CaptureError: Error {
    case displayNotFound
    case windowNotFound
    case cropFailed
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
