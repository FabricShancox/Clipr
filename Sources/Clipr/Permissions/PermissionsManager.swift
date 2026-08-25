import Cocoa
import ApplicationServices

struct PermissionsManager {
    static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettingsPrivacyPane(_ pane: PrivacyPane) {
        guard let url = URL(string: pane.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }
}
