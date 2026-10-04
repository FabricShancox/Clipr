import Cocoa

/// Shows the single Preferences window and routes its change callbacks to the app.
@MainActor
final class PreferencesPresenter {
    private let settings: SettingsStore
    private let hotkeys: HotkeyCoordinator
    private let onSaveFolderChanged: () -> Void
    private let onCaptureCursorChanged: () -> Void
    private var controller: PreferencesWindowController?

    init(settings: SettingsStore, hotkeys: HotkeyCoordinator,
         onSaveFolderChanged: @escaping () -> Void, onCaptureCursorChanged: @escaping () -> Void) {
        self.settings = settings
        self.hotkeys = hotkeys
        self.onSaveFolderChanged = onSaveFolderChanged
        self.onCaptureCursorChanged = onCaptureCursorChanged
    }

    var window: NSWindow? { controller?.window }

    func open() {
        // Reuse the open window rather than building a second one. A new controller each time left
        // the previous window on screen with its bindings still live, so two Preferences windows
        // could write to `SettingsStore` and re-register hotkeys independently.
        if let existing = controller {
            WindowPresenter.bringToFront(existing, regardless: true)
            return
        }
        let controller = PreferencesWindowController(
            settings: settings,
            onHotkeysChanged: { [weak self] in self?.hotkeys.reregisterAppHotkeys() },
            onSaveFolderChanged: { [weak self] in self?.onSaveFolderChanged() },
            onCaptureCursorChanged: { [weak self] in self?.onCaptureCursorChanged() },
            // Clipr's own hotkeys are off while a shortcut is being recorded, so pressing the
            // current capture combo records it instead of taking a screenshot.
            onHotkeyRecording: { [weak self] recording in self?.hotkeys.setRecording(recording) }
        )
        self.controller = controller
        // Cleared on close so the next Preferences request builds a fresh window rather than
        // trying to reuse a closed one.
        if let window = controller.window {
            let box = ObserverTokenBox()
            box.token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                // Delivered on the main queue.
                MainActor.assumeIsolated { self?.controller = nil }
                if let token = box.token { NotificationCenter.default.removeObserver(token) }
            }
        }
        // Clipr is a menu-bar app, so it usually isn't active when Preferences is chosen; showing
        // the window without activating first left it behind whatever app the user was in.
        WindowPresenter.bringToFront(controller, regardless: true)
    }
}

/// Holds a notification observer's token so the observer's own closure can remove it.
private final class ObserverTokenBox: @unchecked Sendable {
    var token: NSObjectProtocol?
}
