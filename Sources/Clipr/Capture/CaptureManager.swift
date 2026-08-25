import Cocoa
import ScreenCaptureKit

final class CaptureManager {
    private let storage: StorageManager
    var onCaptureFinished: ((URL, NSImage) -> Void)?

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
                    image = try await Self.captureArea(rect, on: screen)
                case .fullScreen(let screen):
                    image = try await Self.captureFullScreen(screen)
                case .window(let windowInfo):
                    image = try await Self.captureWindow(windowInfo)
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

    private static func captureFullScreen(_ screen: NSScreen) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func captureArea(_ rect: CGRect, on screen: NSScreen) async throws -> NSImage {
        let fullImage = try await captureFullScreen(screen)
        guard let cgImage = fullImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureError.cropFailed
        }
        // `rect` arrives from CaptureOverlayView in the overlay's VIEW-LOCAL POINTS space (the
        // overlay view fills `screen.frame`, which is in points, and the rect comes straight from
        // a SwiftUI DragGesture). `cgImage` above, however, was captured at the display's native
        // PIXEL resolution: `captureFullScreen` sets `SCStreamConfiguration.width`/`.height` to
        // `display.width`/`display.height` from `SCDisplay`, which are pixel dimensions. On any
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

    private static func captureWindow(_ windowInfo: WindowInfo) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let scWindow = content.windows.first(where: { $0.windowID == windowInfo.windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()
        config.width = Int(windowInfo.bounds.width)
        config.height = Int(windowInfo.bounds.height)
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
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
