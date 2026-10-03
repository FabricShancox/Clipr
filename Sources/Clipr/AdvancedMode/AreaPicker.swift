// Sources/Clipr/AdvancedMode/AreaPicker.swift
import Cocoa

/// The one-time area selection for Fixed area scope, reusing the normal capture overlay.
/// Choosing a whole screen or a window in the overlay sets the area to that screen or window.
enum AreaPicker {
    static func pick(showsCursor: Bool, completion: @escaping (CGRect?) -> Void) {
        Task { @MainActor in
            let frozen: [CGDirectDisplayID: NSImage]
            do {
                frozen = try await CaptureManager.snapshotScreens(NSScreen.screens, showsCursor: showsCursor)
            } catch {
                NSLog("Clipr: area selection failed: \(error)")
                return completion(nil)
            }
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
