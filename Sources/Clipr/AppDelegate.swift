import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItemController = StatusItemController()
    let settings = SettingsStore()
    // HotkeyManager installs a process-wide Carbon event handler in its init and has no
    // teardown logic, so it must live for the entire process lifetime as a plain stored
    // property (never optional, never replaced).
    let hotkeyManager = HotkeyManager()
    lazy var storage = StorageManager(baseFolder: settings.saveFolder)
    lazy var captureManager = CaptureManager(storage: storage)
    lazy var clickCaptureManager = ClickCaptureManager(storage: storage)
    var preferencesWindowController: PreferencesWindowController?

    // NSWindow does NOT retain its NSWindowController, so any window controller created as a
    // local `let`/`var` and merely shown would be deallocated the moment the enclosing function
    // returns, silently breaking its close/finish callbacks. Both of the window controllers this
    // delegate opens directly (EditorWindowController from a top-level capture, and
    // ReviewWindowController from stopping Advanced Mode) are therefore kept alive in an array
    // until they signal they're done, mirroring the same pattern ReviewWindowController itself
    // already uses internally for the editors it opens.
    private var openEditors: [EditorWindowController] = []
    private var openReviewWindows: [ReviewWindowController] = []

    private enum HotkeyID: UInt32 {
        case capture = 1
        case advancedMode = 2
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        captureManager.onCaptureFinished = { [weak self] rawURL, image in
            guard let self else { return }
            let editor = EditorWindowController(image: image, rawURL: rawURL, storage: self.storage)
            self.openEditors.append(editor)
            editor.onFinished = { [weak self, weak editor] in
                guard let self, let editor else { return }
                self.openEditors.removeAll { $0 === editor }
            }
            editor.showWindow(nil)
        }

        statusItemController.onCaptureNow = { [weak self] in self?.performCapture() }
        statusItemController.onToggleAdvancedMode = { [weak self] in self?.toggleAdvancedMode() }
        statusItemController.onOpenPreferences = { [weak self] in self?.openPreferences() }

        registerHotkeys()
    }

    private func registerHotkeys() {
        hotkeyManager.register(settings.captureHotkey, id: HotkeyID.capture.rawValue) { [weak self] in
            self?.performCapture()
        }
        hotkeyManager.register(settings.advancedModeHotkey, id: HotkeyID.advancedMode.rawValue) { [weak self] in
            self?.toggleAdvancedMode()
        }
    }

    /// Both the capture hotkey and the "Capture Now" menu item route through here rather than
    /// calling `captureManager.beginCapture()` directly. `beginCapture()` silently no-ops when
    /// Screen Recording access isn't granted (it only fires the OS's one-time-ever
    /// `CGRequestScreenCaptureAccess()` prompt) - once a user has denied that prompt once, every
    /// later capture attempt would otherwise do nothing with zero feedback and no way to recover.
    /// This wraps that with the same System-Settings-fallback alert already used for Accessibility
    /// denial, so a permanently-denied Screen Recording permission is discoverable and fixable
    /// instead of a silent dead end.
    private func performCapture() {
        if PermissionsManager.hasScreenRecordingPermission() {
            captureManager.beginCapture()
            return
        }
        // Not yet granted: fire the OS prompt (a no-op if already permanently denied - it only
        // ever prompts once per app). `CGRequestScreenCaptureAccess()` has no completion
        // callback, so after giving it a moment to resolve (the user answering the system sheet,
        // or the OS immediately reporting the existing denial), re-check and either proceed or
        // fall back to our own alert with a working "Open System Settings" link.
        PermissionsManager.requestScreenRecordingPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if PermissionsManager.hasScreenRecordingPermission() {
                self.captureManager.beginCapture()
            } else {
                self.showPermissionAlert(pane: .screenRecording, message: "Clipr needs Screen Recording access to capture screenshots.")
            }
        }
    }

    private func toggleAdvancedMode() {
        if clickCaptureManager.isActive {
            let stepURLs = clickCaptureManager.stop()
            statusItemController.setAdvancedModeActive(false)

            let review = ReviewWindowController(stepURLs: stepURLs, storage: storage)
            openReviewWindows.append(review)
            // ReviewWindowController has no onFinished-style closure (unlike
            // EditorWindowController), so its close is observed externally via
            // NSWindow.willCloseNotification instead of touching that file.
            if let window = review.window {
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak review] _ in
                    guard let self, let review else { return }
                    self.openReviewWindows.removeAll { $0 === review }
                }
            }
            review.showWindow(nil)
        } else {
            // Self-exclusion: keep Clipr's own on-screen windows (the menu bar status item,
            // an open Preferences window, any in-progress editor windows) from being captured
            // as if they were a step the user clicked through.
            clickCaptureManager.ownWindowIDs = currentOwnWindowIDs()
            do {
                _ = try clickCaptureManager.start()
                statusItemController.setAdvancedModeActive(true)
            } catch ClickCaptureError.accessibilityNotGranted {
                showPermissionAlert(pane: .accessibility, message: "Clipr needs Accessibility access to detect clicks for Advanced Mode.")
            } catch {
                NSLog("Clipr: failed to start advanced mode: \(error)")
            }
        }
    }

    private func currentOwnWindowIDs() -> Set<CGWindowID> {
        var ids: Set<CGWindowID> = []
        let windows: [NSWindow?] = [statusItemController.statusItem.button?.window, preferencesWindowController?.window]
            + openEditors.map { $0.window }
            + openReviewWindows.map { $0.window }
        for window in windows {
            if let number = window?.windowNumber, let id = CGWindowID(exactly: number) {
                ids.insert(id)
            }
        }
        return ids
    }

    private func openPreferences() {
        let controller = PreferencesWindowController(settings: settings, onHotkeysChanged: { [weak self] in
            self?.hotkeyManager.unregister(id: HotkeyID.capture.rawValue)
            self?.hotkeyManager.unregister(id: HotkeyID.advancedMode.rawValue)
            self?.registerHotkeys()
        })
        preferencesWindowController = controller
        controller.showWindow(nil)
    }

    private func showPermissionAlert(pane: PrivacyPane, message: String) {
        let alert = NSAlert()
        alert.messageText = "Permission Required"
        alert.informativeText = message
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            PermissionsManager.openSystemSettingsPrivacyPane(pane)
        }
    }
}
