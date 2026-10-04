import Cocoa

/// Every `NSAlert` Clipr shows, built the same way: a title, optional detail, a style (NSAlert's
/// own default, `.warning`, unless given) and buttons in order (just OK when none are given).
enum Alerts {
    static func make(_ title: String, _ detail: String? = nil, style: NSAlert.Style = .warning,
                     buttons: [String] = []) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        if let detail { alert.informativeText = detail }
        alert.alertStyle = style
        for button in buttons { alert.addButton(withTitle: button) }
        return alert
    }

    /// Runs the alert app-modally. `activate` brings Clipr forward first — needed when the alert
    /// follows a hotkey or a background check, with another app frontmost.
    @discardableResult
    static func run(_ title: String, _ detail: String? = nil, style: NSAlert.Style = .warning,
                    buttons: [String] = [], activate: Bool = false) -> NSApplication.ModalResponse {
        let alert = make(title, detail, style: style, buttons: buttons)
        if activate { WindowPresenter.activateApp() }
        return alert.runModal()
    }

    /// A sheet on `window`, or app-modal when there's no window to attach to. `completion` gets the
    /// button the user picked either way.
    static func present(_ title: String, _ detail: String? = nil, style: NSAlert.Style = .warning,
                        buttons: [String] = [], on window: NSWindow?,
                        completion: ((NSApplication.ModalResponse) -> Void)? = nil) {
        let alert = make(title, detail, style: style, buttons: buttons)
        if let window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            let response = alert.runModal()
            completion?(response)
        }
    }

    /// "Permission Required", with a button that deep-links to the System Settings privacy pane.
    /// Used for both Screen Recording and Accessibility denials.
    static func permissionRequired(pane: PrivacyPane, message: String) {
        if run("Permission Required", message, buttons: ["Open System Settings", "Cancel"]) == .alertFirstButtonReturn {
            PermissionsManager.openSystemSettingsPrivacyPane(pane)
        }
    }

    /// Advanced Mode captures the frontmost app window on every click — it has no drag-to-select-
    /// an-area interaction, and clicking somewhere with no real window under the cursor (e.g. the
    /// Desktop) captures nothing. Naming the actual interaction model here is cheaper than a UI
    /// redesign.
    static func noStepsCaptured() {
        run("No Steps Captured", "Advanced Mode captures the frontmost app window each time you click it — not a dragged area. Click inside a real app window (not the empty Desktop) to record a step.",
            activate: true)
    }
}
