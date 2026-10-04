// Sources/Clipr/AdvancedMode/AreaPicker.swift
import Cocoa

/// The one-time area selection for Fixed area scope, reusing the normal capture overlay.
/// Choosing a whole screen or a window in the overlay sets the area to that screen or window.
enum AreaPicker {
    /// Set while the screens are being snapshotted, before the overlay is up.
    @MainActor private static var snapshotInFlight = false

    /// Advanced Mode isn't active while the user picks, so a second hotkey press would otherwise
    /// stack a second snapshot (with the first overlay in it) and overlay. A request while a
    /// selection is being prepared or is on screen is ignored (completes with `nil`). Derived from
    /// the overlay's windows rather than a flag cleared on completion, since another capture can
    /// dismiss the overlay without reporting back here.
    @MainActor static var isPicking: Bool {
        snapshotInFlight || NSApp.windows.contains { $0 is CaptureOverlayWindow && $0.isVisible }
    }

    static func pick(showsCursor: Bool, completion: @escaping (CGRect?) -> Void) {
        Task { @MainActor in
            guard !isPicking else { return completion(nil) }
            snapshotInFlight = true
            let frozen: [CGDirectDisplayID: NSImage]
            do {
                frozen = try await CaptureManager.snapshotScreens(NSScreen.screens, showsCursor: showsCursor)
            } catch {
                snapshotInFlight = false
                NSLog("Clipr: area selection failed: \(error)")
                return completion(nil)
            }
            snapshotInFlight = false
            CaptureOverlayWindow.showAll(frozenScreens: frozen) { result in
                CaptureOverlayWindow.restoreHiddenWindows()
                let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                switch result {
                case .area(let rect, let screen):
                    completion(StepGeometry.globalTopLeftRect(viewLocal: rect, screenFrame: screen.frame, primaryScreenHeight: primaryHeight))
                case .fullScreen(let screen):
                    completion(StepGeometry.globalTopLeftFrame(ofScreenFrame: screen.frame, primaryScreenHeight: primaryHeight))
                case .window(let info):
                    completion(info.bounds)
                case .cancelled:
                    completion(nil)
                }
            }
        }
    }
}
