import Cocoa
import UniformTypeIdentifiers

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
    var preferencesWindowController: PreferencesWindowController?

    // NSWindow does NOT retain its NSWindowController, so a locally-created one merely shown
    // would be deallocated immediately. Kept alive here until it signals it's done;
    // `AdvancedModeCoordinator` does the same internally for its Review windows.
    private var openEditors: [EditorWindowController] = []

    private enum HotkeyID: UInt32 {
        case capture = 1
        case advancedMode = 2
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `.regular`, not `.accessory`: Clipr is a regular app with a Dock icon and an app-switcher
        // entry, not a menu-bar-only utility. The status item stays as a second way in. This also
        // means the app owns the menu bar when frontmost, so it has to supply one.
        NSApp.setActivationPolicy(.regular)
        installMainMenu()

        applyCaptureCursorSetting()

        captureManager.onCaptureFinished = { [weak self] rawURL, image in
            self?.openEditor(image: image, rawURL: rawURL)
        }
        captureManager.onCaptureFailed = { [weak self] error in
            self?.showCaptureFailure(error)
        }
        advancedMode.onStepCaptured = { [weak self] count in
            self?.statusItemController.setAdvancedModeStepCount(count)
        }

        statusItemController.onCaptureNow = { [weak self] in self?.performCapture() }
        statusItemController.onOpenImage = { [weak self] in self?.openImage() }
        statusItemController.onToggleAdvancedMode = { [weak self] in self?.toggleAdvancedMode() }
        statusItemController.onOpenPreferences = { [weak self] in self?.openPreferences() }
        statusItemController.onCheckForUpdates = { [weak self] in self?.updateChecker.checkNow() }

        registerHotkeys()
        updateChecker.checkInBackgroundIfDue()
    }

    /// Shows a capture in the editor, reusing an already-open window rather than adding another.
    ///
    /// Every capture used to build its own `EditorWindowController`, so a run of screenshots left
    /// a stack of windows on screen — each pinned to the full visible frame and holding its own
    /// full-resolution image — with no guarantee the newest was the one in front. Reuse matches
    /// what clicking a Recents thumbnail already does: the capture is swapped into the window in
    /// place. A second editor only appears if the user closed the last one.
    private func openEditor(image: NSImage, rawURL: URL) {
        if let existing = frontmostEditor() {
            existing.present(image: image, rawURL: rawURL)
            return
        }
        let editor = EditorWindowController(image: image, rawURL: rawURL, storage: storage, settings: settings)
        openEditors.append(editor)
        editor.onFinished = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.openEditors.removeAll { $0 === editor }
        }
        editor.showWindow(nil)
    }

    /// The open editor nearest the front, so a capture lands in the window the user was last
    /// looking at rather than in whichever one happens to be oldest. `NSApp.orderedWindows` is
    /// front-to-back; the fallback covers an editor that's currently miniaturized, and so absent
    /// from that ordering.
    private func frontmostEditor() -> EditorWindowController? {
        for window in NSApp.orderedWindows {
            if let editor = openEditors.first(where: { $0.window === window }) { return editor }
        }
        return openEditors.last
    }

    /// Opens the editor on an existing image file instead of a fresh capture. The picked file
    /// becomes this editor's "raw" file directly, so auto-save writes its `_edited` companion
    /// right next to wherever the user chose to open it from.
    private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Open Image in Clipr"
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        openEditor(image: image, rawURL: url)
    }

    private func registerHotkeys() {
        var rejected: [String] = []
        if !hotkeyManager.register(settings.captureHotkey, id: HotkeyID.capture.rawValue, handler: { [weak self] in
            self?.performCapture()
        }) {
            rejected.append("\(settings.captureHotkey.displayString) (Capture)")
        }
        if !hotkeyManager.register(settings.advancedModeHotkey, id: HotkeyID.advancedMode.rawValue, handler: { [weak self] in
            self?.toggleAdvancedMode()
        }) {
            rejected.append("\(settings.advancedModeHotkey.displayString) (Advanced Mode)")
        }
        guard !rejected.isEmpty else { return }

        // The registration that failed has already dropped whatever was bound before, so staying
        // quiet would leave the user with a hotkey that simply stopped working and no clue why.
        let alert = NSAlert()
        alert.messageText = rejected.count == 1 ? "A shortcut couldn't be registered" : "Some shortcuts couldn't be registered"
        alert.informativeText = """
            \(rejected.joined(separator: "\n"))

            Another app or macOS is probably already using \(rejected.count == 1 ? "it" : "them"). \
            Pick a different combination in Preferences.
            """
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Tells the user a capture failed, pointing at Screen Recording when that's the likely cause.
    ///
    /// `hasScreenRecordingPermission` is checked before the overlay appears, but the answer is
    /// cached for the process: revoking access in System Settings mid-session still passes that
    /// check, so the failure only shows up here, once ScreenCaptureKit refuses.
    private func showCaptureFailure(_ error: Error) {
        // ScreenCaptureKit reports its own failures under this domain; the string constant avoids
        // importing ScreenCaptureKit here just for it.
        let isPermissionProblem = (error as NSError).domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
        if isPermissionProblem {
            showPermissionAlert(
                pane: .screenRecording,
                message: "Clipr couldn't capture the screen. If you've recently changed Screen Recording access, it may need to be re-granted — and Clipr restarted."
            )
            return
        }
        let alert = NSAlert()
        alert.messageText = "Capture failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Routes both the capture hotkey and "Capture Now" through here rather than calling
    /// `captureManager.beginCapture()` directly — a permanently-denied Screen Recording
    /// permission otherwise silently does nothing, with no way to recover.
    private func performCapture() {
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
                self.captureManager.beginCapture()
            } else {
                showPermissionAlert(pane: .screenRecording, message: "Clipr needs Screen Recording access to capture screenshots.")
            }
        }
    }

    private func toggleAdvancedMode() {
        switch advancedMode.toggle(ownWindowIDs: currentOwnWindowIDs()) {
        case .started:
            statusItemController.setAdvancedModeActive(true)
        case .accessibilityNotGranted:
            showPermissionAlert(pane: .accessibility, message: "Clipr needs Accessibility access to detect clicks for Advanced Mode.")
        case .startFailed(let error):
            // Surfaced, not just logged: the user asked for this and nothing visible would
            // happen otherwise — the menu would simply stay on "Start Advanced Mode".
            NSLog("Clipr: failed to start advanced mode: \(error)")
            let alert = NSAlert()
            alert.messageText = "Couldn't start Advanced Mode"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        case .stoppedNoSteps:
            statusItemController.setAdvancedModeActive(false)
            showNoStepsCapturedAlert()
        case .stopped(let review):
            statusItemController.setAdvancedModeActive(false)
            review.showWindow(nil)
        }
    }

    private func currentOwnWindowIDs() -> Set<CGWindowID> {
        windowIDs(of: [statusItemController.statusItem.button?.window, preferencesWindowController?.window]
            + openEditors.map { $0.window }
            + advancedMode.reviewWindows)
    }

    /// Quitting abandons every editor's pending 800ms auto-save debounce, so the last edit in each
    /// open window would be lost silently. Flushing here writes them synchronously first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for editor in openEditors {
            editor.flushPendingSave()
        }
        return .terminateNow
    }

    /// Target for the main menu's Preferences item — see `MainMenu.swift`. A menu item needs an
    /// `@objc` selector, which `openPreferences` (private, non-`@objc`) can't be.
    @objc func showPreferencesFromMenu() {
        openPreferences()
    }

    @objc func checkForUpdatesFromMenu() {
        updateChecker.checkNow()
    }

    private func openPreferences() {
        // Reuse the open window rather than building a second one. A new controller each time left
        // the previous window on screen with its bindings still live, so two Preferences windows
        // could write to `SettingsStore` and re-register hotkeys independently.
        if let existing = preferencesWindowController {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = PreferencesWindowController(
            settings: settings,
            onHotkeysChanged: { [weak self] in
                self?.hotkeyManager.unregister(id: HotkeyID.capture.rawValue)
                self?.hotkeyManager.unregister(id: HotkeyID.advancedMode.rawValue)
                self?.registerHotkeys()
            },
            // `storage` is a long-lived object created once at launch from the then-current save
            // folder, and CaptureManager/AdvancedModeCoordinator/the editors all hold a reference
            // to that same instance. Re-pointing its `baseFolder` (rather than rebuilding it)
            // makes a save-folder change in Preferences apply immediately for all of them.
            onSaveFolderChanged: { [weak self] in
                guard let self else { return }
                self.storage.baseFolder = self.settings.saveFolder
            },
            onCaptureCursorChanged: { [weak self] in self?.applyCaptureCursorSetting() }
        )
        preferencesWindowController = controller
        // Cleared on close so the next Preferences request builds a fresh window rather than
        // trying to reuse a closed one.
        if let window = controller.window {
            var token: NSObjectProtocol?
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                self?.preferencesWindowController = nil
                if let token { NotificationCenter.default.removeObserver(token) }
            }
        }
        controller.showWindow(nil)
    }

    /// `CaptureManager`/`AdvancedModeCoordinator` each hold their own `captureCursor` copy rather
    /// than reading `SettingsStore` live, so both need re-syncing here — at launch, and again
    /// whenever the Preferences toggle changes.
    private func applyCaptureCursorSetting() {
        captureManager.captureCursor = settings.captureCursor
        advancedMode.captureCursor = settings.captureCursor
    }
}
