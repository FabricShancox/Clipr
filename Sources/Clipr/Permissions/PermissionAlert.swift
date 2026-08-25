import Cocoa

/// Shows a "Permission Required" alert with a button that deep-links to the relevant System
/// Settings privacy pane. Used by `AppDelegate` for both Screen Recording and Accessibility
/// denials — the only difference between call sites is which pane and what message to show.
func showPermissionAlert(pane: PrivacyPane, message: String) {
    let alert = NSAlert()
    alert.messageText = "Permission Required"
    alert.informativeText = message
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
        PermissionsManager.openSystemSettingsPrivacyPane(pane)
    }
}
