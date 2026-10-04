import Cocoa

/// App lifecycle and wiring. The work itself lives in the collaborators: `EditorPresenter`
/// (editor windows), `AdvancedModeController` (sessions), `PreferencesPresenter` and
/// `HotkeyCoordinator`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItemController = StatusItemController()
    let settings = SettingsStore()
    // Installs a process-wide Carbon event handler in its init with no teardown logic, so it
    // must live for the whole process lifetime as a plain stored property.
    let hotkeyManager = HotkeyManager()
    let updateChecker = UpdateChecker()
    lazy var storage = StorageManager(baseFolder: settings.saveFolder)
    lazy var captureManager = CaptureManager(storage: storage)
    lazy var advancedMode = AdvancedModeCoordinator(storage: storage)
    private lazy var hotkeys = HotkeyCoordinator(manager: hotkeyManager, settings: settings)
    private lazy var editors = EditorPresenter(storage: storage, settings: settings)
    private lazy var advancedModeController = AdvancedModeController(
        coordinator: advancedMode, settings: settings, statusItemController: statusItemController, hotkeys: hotkeys)
    private lazy var preferences = PreferencesPresenter(
        settings: settings, hotkeys: hotkeys,
        // `storage` is a long-lived object created once at launch from the then-current save
        // folder, and CaptureManager/AdvancedModeCoordinator/the editors all hold a reference
        // to that same instance. Re-pointing its `baseFolder` (rather than rebuilding it)
        // makes a save-folder change in Preferences apply immediately for all of them.
        onSaveFolderChanged: { [weak self] in
            guard let self else { return }
            self.storage.baseFolder = self.settings.saveFolder
        },
        onCaptureCursorChanged: { [weak self] in self?.applyCaptureCursorSetting() })

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `.regular`, not `.accessory`: Clipr is a regular app with a Dock icon and an app-switcher
        // entry, not a menu-bar-only utility. The status item stays as a second way in. This also
        // means the app owns the menu bar when frontmost, so it has to supply one.
        NSApp.setActivationPolicy(.regular)
        installMainMenu()

        applyCaptureCursorSetting()

        captureManager.onCaptureFinished = { [weak self] rawURL, image in
            self?.editors.openEditor(image: image, rawURL: rawURL)
        }
        captureManager.onCaptureFailed = { error in
            CaptureFailureAlert.show(error)
        }
        advancedMode.captureReplacement = { [weak self] done in
            guard let self else { return done(nil) }
            self.captureManager.captureImage(completion: done)
        }
        advancedModeController.otherOwnWindows = { [weak self] in
            guard let self else { return [] }
            return [self.statusItemController.statusItem.button?.window, self.preferences.window] + self.editors.windows
        }

        statusItemController.onCaptureNow = { [weak self] in self?.performCapture() }
        statusItemController.onOpenImage = { [weak self] in self?.editors.openImage() }
        statusItemController.onToggleAdvancedMode = { [weak self] in self?.advancedModeController.toggle() }
        statusItemController.onReviewLastSession = { [weak self] in self?.advancedModeController.reviewLastSession() }
        statusItemController.onOpenPreferences = { [weak self] in self?.preferences.open() }
        statusItemController.onCheckForUpdates = { [weak self] in self?.updateChecker.checkNow() }

        hotkeys.onCapture = { [weak self] in self?.performCapture() }
        hotkeys.onToggleAdvancedMode = { [weak self] in self?.advancedModeController.toggle() }
        hotkeys.registerAppHotkeys()
        updateChecker.checkInBackgroundIfDue()
    }

    /// Routes both the capture hotkey and "Capture Now" through here rather than calling
    /// `captureManager.beginCapture()` directly — a permanently-denied Screen Recording
    /// permission otherwise silently does nothing, with no way to recover.
    private func performCapture() {
        // A modal alert, open panel or sheet would sit under the overlay, which then gets no
        // events — a stuck screen. See `ModalHotkeyGuard`.
        guard !ModalHotkeyGuard.shouldIgnoreNow() else { NSSound.beep(); return }
        if PermissionsManager.hasScreenRecordingPermission() {
            captureManager.beginCapture()
            return
        }
        // Not yet granted: fire the OS prompt (a no-op if already permanently denied). It has no
        // completion callback, so re-check shortly after and fall back to our own alert.
        PermissionsManager.requestScreenRecordingPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if PermissionsManager.hasScreenRecordingPermission() {
                MainActor.assumeIsolated { self.captureManager.beginCapture() }
            } else {
                Alerts.permissionRequired(pane: .screenRecording, message: "Clipr needs Screen Recording access to capture screenshots.")
            }
        }
    }

    /// Clicking the Dock icon with no windows open used to do nothing. Bring back an editor that's
    /// still around (e.g. miniaturized), otherwise open Preferences — the one window Clipr can
    /// always show, and the place to find the capture shortcut.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let editor = editors.frontmostEditor() {
            editor.window?.deminiaturize(nil)
            WindowPresenter.bringToFront(editor, regardless: true)
        } else {
            preferences.open()
        }
        return false
    }

    /// Quitting abandons every editor's pending 800ms auto-save debounce (and each Review's 0.5s
    /// caption debounce), so the last edit in each open window would be lost silently. Flushing
    /// here writes them synchronously first.
    ///
    /// A session still recording is stopped first, and quit waits (bounded) for its last steps and
    /// session.json — otherwise steps already taken could be lost or left out of the manifest.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        editors.flushPendingSaves()
        advancedMode.flushOpenReviews()
        guard advancedModeController.isRecording else { return .terminateNow }
        var replied = false
        let reply = {
            guard !replied else { return }
            replied = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        advancedModeController.stopForQuit(timeout: Self.quitFlushTimeout) { reply() }
        // Belt and braces: the stop's own flush is bounded too, but quit must never hang.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.quitFlushTimeout + 0.5) { reply() }
        return .terminateLater
    }

    /// The longest quit waits for a recording session's last steps to be written.
    private static let quitFlushTimeout: TimeInterval = 3

    /// Target for the main menu's Preferences item — see `MainMenu.swift`. A menu item needs an
    /// `@objc` selector.
    @objc func showPreferencesFromMenu() {
        preferences.open()
    }

    @objc func checkForUpdatesFromMenu() {
        updateChecker.checkNow()
    }

    /// `CaptureManager`/`AdvancedModeCoordinator` each hold their own `captureCursor` copy rather
    /// than reading `SettingsStore` live, so both need re-syncing here — at launch, and again
    /// whenever the Preferences toggle changes.
    private func applyCaptureCursorSetting() {
        captureManager.captureCursor = settings.captureCursor
        advancedMode.captureCursor = settings.captureCursor
    }
}
