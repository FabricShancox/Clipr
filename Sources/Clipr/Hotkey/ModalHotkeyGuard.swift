import Cocoa

/// Whether a global hotkey that would put up a full-screen overlay should be ignored right now.
///
/// While an alert or open panel runs modally (or a sheet is up), the capture overlay would appear
/// above it but receive no mouse or key events — no drag, no Esc — while the dialog the user would
/// need to dismiss sits underneath. The only way out was Force Quit. So the hotkey beeps instead.
enum ModalHotkeyGuard {
    static func shouldIgnore(hasModalWindow: Bool, keyWindowHasSheet: Bool, keyWindowIsSheet: Bool) -> Bool {
        hasModalWindow || keyWindowHasSheet || keyWindowIsSheet
    }

    /// The live check against the running app.
    static func shouldIgnoreNow(_ app: NSApplication = NSApp) -> Bool {
        shouldIgnore(
            hasModalWindow: app.modalWindow != nil,
            keyWindowHasSheet: app.keyWindow?.attachedSheet != nil,
            keyWindowIsSheet: app.keyWindow?.isSheet ?? false
        )
    }
}
