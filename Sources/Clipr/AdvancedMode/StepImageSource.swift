// Sources/Clipr/AdvancedMode/StepImageSource.swift
import Cocoa

enum CaptureTarget: Equatable {
    case frontmostWindow
    case screenContaining(CGPoint)
    case area(CGRect)
}

struct CapturedFrame {
    let image: NSImage
    /// Quartz global position of the image's top-left corner — what `StepGeometry` subtracts.
    let origin: CGPoint
    let appName: String?
}

protocol StepImageSource: AnyObject {
    var ownWindowIDs: Set<CGWindowID> { get set }
    func capture(_ target: CaptureTarget, showsCursor: Bool) async throws -> CapturedFrame?
}

final class LiveStepImageSource: StepImageSource {
    var ownWindowIDs: Set<CGWindowID> = []

    func capture(_ target: CaptureTarget, showsCursor: Bool) async throws -> CapturedFrame? {
        let appName = await MainActor.run { NSWorkspace.shared.frontmostApplication?.localizedName }
        switch target {
        case .frontmostWindow:
            guard let window = await MainActor.run(body: { frontmostWindow() }) else { return nil }
            let image = try await CaptureManager.captureWindow(window, showsCursor: showsCursor)
            return CapturedFrame(image: image, origin: window.bounds.origin, appName: appName)
        case .screenContaining(let point):
            guard let match = await MainActor.run(body: { Self.screen(containing: point) }) else { return nil }
            let (screen, frame) = match
            let image = try await CaptureManager.captureFullScreen(screen, showsCursor: showsCursor)
            return CapturedFrame(image: image, origin: frame.origin, appName: appName)
        case .area(let area):
            let center = CGPoint(x: area.midX, y: area.midY)
            guard let match = await MainActor.run(body: { Self.screen(containing: center) }) else { return nil }
            let (screen, frame) = match
            let full = try await CaptureManager.captureFullScreen(screen, showsCursor: showsCursor)
            let local = area.offsetBy(dx: -frame.minX, dy: -frame.minY)
            guard let cropped = CaptureGeometry.cropped(full, to: local) else { return nil }
            return CapturedFrame(image: cropped.image, origin: CGPoint(x: frame.minX + cropped.rect.minX, y: frame.minY + cropped.rect.minY), appName: appName)
        }
    }

    /// Same rules Advanced Mode has always used: never Clipr itself, never a window Clipr owns.
    @MainActor
    private func frontmostWindow() -> WindowInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        guard let window = WindowPicker.frontmostWindow(ownedBy: app.processIdentifier, in: WindowPicker.onScreenWindows()),
              !ownWindowIDs.contains(window.windowID) else { return nil }
        return window
    }

    @MainActor
    static func screen(containing point: CGPoint) -> (NSScreen, CGRect)? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        for screen in NSScreen.screens {
            let frame = StepGeometry.globalTopLeftFrame(ofScreenFrame: screen.frame, primaryScreenHeight: primaryHeight)
            if frame.contains(point) { return (screen, frame) }
        }
        return nil
    }
}
