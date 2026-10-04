import Cocoa
import ScreenCaptureKit

/// Captures steps from the screen with ScreenCaptureKit.
final class LiveStepImageSource: StepImageSource {
    var ownWindowIDs: Set<CGWindowID> = []

    func capture(_ target: CaptureTarget, showsCursor: Bool) async throws -> CapturedFrame? {
        // Read once so the reported app and the window we capture can't disagree if focus changes.
        let app = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        let appName = app?.localizedName
        switch target {
        case .frontmostWindow:
            guard let window = await MainActor.run(body: { frontmostWindow(of: app) }) else { return nil }
            let image = try await CaptureManager.captureWindow(window, showsCursor: showsCursor)
            return CapturedFrame(image: image, origin: window.bounds.origin, appName: appName)
        case .window(let clicked):
            if let window = await MainActor.run(body: { onScreenWindow(clicked) }),
               let image = try? await CaptureManager.captureWindow(window, showsCursor: showsCursor) {
                return CapturedFrame(image: image, origin: window.bounds.origin, appName: clicked.appName ?? appName)
            }
            // Gone (the click closed it): the frontmost window, without the click marked on it.
            guard let window = await MainActor.run(body: { frontmostWindow(of: app) }) else { return nil }
            let image = try await CaptureManager.captureWindow(window, showsCursor: showsCursor)
            return CapturedFrame(image: image, origin: window.bounds.origin, appName: appName, marksClick: false)
        case .screenContaining(let point):
            guard let match = await MainActor.run(body: { Self.screen(containing: point) }) else { return nil }
            let image = try await Self.captureScreen(match, showsCursor: showsCursor)
            return CapturedFrame(image: image, origin: match.frame.origin, appName: appName)
        case .area(let area):
            let center = CGPoint(x: area.midX, y: area.midY)
            guard let match = await MainActor.run(body: { Self.screen(containing: center) }) else { return nil }
            let frame = match.frame
            let full = try await Self.captureScreen(match, showsCursor: showsCursor)
            let local = area.offsetBy(dx: -frame.minX, dy: -frame.minY)
            guard let cropped = CaptureGeometry.cropped(full, to: local) else { return nil }
            return CapturedFrame(image: cropped.image, origin: CGPoint(x: frame.minX + cropped.rect.minX, y: frame.minY + cropped.rect.minY), appName: appName)
        }
    }

    /// Same rules Advanced Mode has always used: never Clipr itself, never a window Clipr owns.
    @MainActor
    private func frontmostWindow(of app: NSRunningApplication?) -> WindowInfo? {
        guard let app,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        guard let window = WindowPicker.frontmostWindow(ownedBy: app.processIdentifier, in: WindowPicker.onScreenWindows()),
              !ownWindowIDs.contains(window.windowID) else { return nil }
        return window
    }

    /// One of the capture's on-screen windows, as far as deciding what to leave out goes.
    struct ScreenWindow: Equatable {
        let windowID: CGWindowID
        let ownerPID: pid_t?
        let layer: Int
    }

    static let statusItemLayer = Int(CGWindowLevelForKey(.statusWindow))

    /// Every window Clipr owns except its menu-bar icon: the Pause/Stop panel, its tooltips,
    /// Review, editors. Named explicitly rather than trusting `sharingType = .none`, which
    /// ScreenCaptureKit is reported not to honour on recent macOS.
    static func ownWindowsToExclude(_ windows: [ScreenWindow], ownPID: pid_t) -> Set<CGWindowID> {
        Set(windows.filter { $0.ownerPID == ownPID && $0.layer != statusItemLayer }.map(\.windowID))
    }

    /// A full-display capture for Screen and Fixed-area steps, without Clipr's own windows.
    static func captureScreen(_ screen: ScreenMatch, showsCursor: Bool) async throws -> NSImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let excluded = ownWindowsToExclude(
            content.windows.map { ScreenWindow(windowID: $0.windowID, ownerPID: $0.owningApplication?.processID, layer: $0.windowLayer) },
            ownPID: ProcessInfo.processInfo.processIdentifier
        )
        let filter = SCContentFilter(display: display, excludingWindows: content.windows.filter { excluded.contains($0.windowID) })
        let config = SCStreamConfiguration()
        config.showsCursor = showsCursor
        // SCDisplay is in points, the configuration in pixels (see `CaptureManager.captureFullScreen`).
        let scale = screen.scale
        config.width = Int((CGFloat(display.width) * scale).rounded())
        config.height = Int((CGFloat(display.height) * scale).rounded())
        let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return NSImage(bitmap: cgImage, scale: scale)
    }

    /// What a Screen or Fixed-area step needs of the display it shoots, read on the main actor so
    /// no `NSScreen` (not `Sendable`) crosses into the capture task.
    struct ScreenMatch: Sendable {
        let displayID: CGDirectDisplayID
        let scale: CGFloat
        /// The screen's frame in Quartz global top-left coordinates.
        let frame: CGRect
    }

    /// The clicked window's current bounds, if it's still on screen and isn't Clipr's.
    @MainActor
    private func onScreenWindow(_ clicked: ClickedWindow) -> WindowInfo? {
        guard clicked.ownerPID != ProcessInfo.processInfo.processIdentifier,
              !ownWindowIDs.contains(clicked.windowID),
              let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, clicked.windowID) as? [[String: Any]],
              let entry = list.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == clicked.windowID }),
              (entry[kCGWindowIsOnscreen as String] as? Bool) == true,
              let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        let bounds = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                            width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return WindowInfo(windowID: clicked.windowID, ownerPID: clicked.ownerPID, bounds: bounds, layer: clicked.layer)
    }

    @MainActor
    static func screen(containing point: CGPoint) -> ScreenMatch? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        for screen in NSScreen.screens {
            let frame = StepGeometry.globalTopLeftFrame(ofScreenFrame: screen.frame, primaryScreenHeight: primaryHeight)
            if frame.contains(point) {
                return ScreenMatch(displayID: screen.displayID, scale: screen.backingScaleFactor, frame: frame)
            }
        }
        return nil
    }
}
