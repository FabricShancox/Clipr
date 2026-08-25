import Cocoa
import ApplicationServices

enum PrivacyPane {
    case screenRecording
    case accessibility

    var settingsURLString: String {
        switch self {
        case .screenRecording:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .accessibility:
            return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }
    }
}

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
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettingsPrivacyPane(_ pane: PrivacyPane) {
        guard let url = URL(string: pane.settingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }
}
