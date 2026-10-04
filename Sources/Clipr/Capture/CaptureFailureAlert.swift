import Cocoa

/// Tells the user a capture failed, pointing at Screen Recording when that's the likely cause.
///
/// `hasScreenRecordingPermission` is checked before the overlay appears, but the answer is
/// cached for the process: revoking access in System Settings mid-session still passes that
/// check, so the failure only shows up here, once ScreenCaptureKit refuses.
@MainActor
enum CaptureFailureAlert {
    static func show(_ error: Error) {
        // ScreenCaptureKit reports its own failures under this domain; the string constant avoids
        // importing ScreenCaptureKit here just for it.
        let isPermissionProblem = (error as NSError).domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
        if isPermissionProblem {
            Alerts.permissionRequired(
                pane: .screenRecording,
                message: "Clipr couldn't capture the screen. If you've recently changed Screen Recording access, it may need to be re-granted — and Clipr restarted."
            )
            return
        }
        // A capture is started from a hotkey while another app is frontmost.
        Alerts.run("Capture failed", error.localizedDescription, activate: true)
    }
}
