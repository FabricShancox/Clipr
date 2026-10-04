// Sources/Clipr/UI/WindowPresenter.swift
import Cocoa

/// Clipr is a menu-bar (accessory) app, so a window shown with a plain `showWindow` can open
/// behind whatever app the user was just in. These bring Clipr — and the window — forward.
enum WindowPresenter {
    static func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Activates Clipr, shows the controller's window and makes it key.
    static func bringToFront(_ controller: NSWindowController) {
        activateApp()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }
}
