import Cocoa

/// The window a click landed on, resolved when the click happens: by the time a delayed capture
/// runs, the click may have opened a new window in front, or closed the menu that was clicked.
struct ClickedWindow: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let layer: Int
    /// The owning app's name, for the caption ("Click **Save** in Pages").
    let appName: String?

    /// Ordinary windows, floating palettes, panels and utility windows: what a Window-scope step
    /// should show. The Dock, the menu bar, pop-up menus and the desktop are not — a click there
    /// is captured as before, from the frontmost app's window.
    var isCapturable: Bool { layer >= 0 && layer < Self.dockLayer }

    static let dockLayer = Int(CGWindowLevelForKey(.dockWindow))
}
