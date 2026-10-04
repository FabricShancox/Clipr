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
    /// The floating Pause/Stop bar — present only while an Advanced Mode session runs.
    private var advancedModePanel: AdvancedModeControlPanel?
    var preferencesWindowController: PreferencesWindowController?

    // NSWindow does NOT retain its NSWindowController, so a locally-created one merely shown
    // would be deallocated immediately. Kept alive here until it signals it's done;
    // `AdvancedModeCoordinator` does the same internally for its Review windows.
    private var openEditors: [EditorWindowController] = []

    private enum HotkeyID: UInt32 {
        case capture = 1
        case advancedMode = 2
        case advancedModeStep = 3
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
        advancedMode.captureReplacement = { [weak self] done in
            guard let self else { return done(nil) }
            MainActor.assumeIsolated { self.captureManager.captureImage(completion: done) }
        }
        advancedMode.onStepCaptured = { [weak self] count in
            self?.statusItemController.setAdvancedModeStepCount(count)
            self?.advancedModePanel?.state.stepCount = count
        }

        statusItemController.onCaptureNow = { [weak self] in self?.performCapture() }
        statusItemController.onOpenImage = { [weak self] in self?.openImage() }
        statusItemController.onToggleAdvancedMode = { [weak self] in self?.toggleAdvancedMode() }
        statusItemController.onReviewLastSession = { [weak self] in self?.reviewLastSession() }
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

    /// Opens the editor on an existing image file instead of a fresh capture.
    ///
    /// The picked file is NOT edited in place: crop and canvas-resize rewrite the editor's raw
    /// file, which used to destroy the user's original (and give a JPEG PNG bytes under its old
    /// name). Unless it's already a PNG in the capture folder, it's imported there as a new PNG
    /// first — see `StorageManager.importForEditing` — and the original is never written to.
    private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Open Image in Clipr"
        // Chosen from the status menu while another app is frontmost: without activating, the
        // panel (and any alert after it) can open behind that app.
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let image: NSImage
        switch DecodeLimits.loadImage(at: url) {
        case .loaded(let loaded):
            image = loaded
        case .unreadable:
            showOpenImageFailure(url, reason: "It isn't an image Clipr can read.")
            return
        case .tooLarge(let width, let height):
            showOpenImageFailure(url, reason: "It is \(width) × \(height) pixels, which is too large to edit.")
            return
        }
        do {
            let editable = try storage.importForEditing(url, image: image)
            openEditor(image: image, rawURL: editable)
        } catch {
            NSLog("Clipr: could not import \(url.lastPathComponent): \(error)")
            let alert = NSAlert()
            alert.messageText = "Couldn't open this image"
            alert.informativeText = "Clipr couldn't copy \(url.lastPathComponent) into your capture folder, so it wasn't opened. The original wasn't changed.\n\n\(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func showOpenImageFailure(_ url: URL, reason: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't open \(url.lastPathComponent)"
        alert.informativeText = reason
        alert.alertStyle = .warning
        alert.runModal()
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
        // A capture is started from a hotkey while another app is frontmost.
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// Routes both the capture hotkey and "Capture Now" through here rather than calling
    /// `captureManager.beginCapture()` directly — a permanently-denied Screen Recording
    /// permission otherwise silently does nothing, with no way to recover.
    private func performCapture() {
        // A modal alert, open panel or sheet would sit under the overlay, which then gets no
        // events — a stuck screen. See `ModalHotkeyGuard`.
        guard !ModalHotkeyGuard.shouldIgnoreNow() else { NSSound.beep(); return }
        if PermissionsManager.hasScreenRecordingPermission() {
            MainActor.assumeIsolated { captureManager.beginCapture() }
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
                showPermissionAlert(pane: .screenRecording, message: "Clipr needs Screen Recording access to capture screenshots.")
            }
        }
    }

    private func toggleAdvancedMode() {
        if advancedMode.isActive {
            unregisterStepHotkey()
            advancedMode.stop { [weak self] review in
                guard let self else { return }
                self.statusItemController.setAdvancedModeActive(false)
                self.hideAdvancedModePanel()
                if let review {
                    review.present()
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    showNoStepsCapturedAlert()
                }
            }
            return
        }
        // Starting puts up an area picker or a recording session over whatever's open; with a
        // modal dialog up that leaves it unreachable. Stopping (above) is always allowed.
        guard !ModalHotkeyGuard.shouldIgnoreNow() else { NSSound.beep(); return }
        let advancedSettings = settings.advancedMode
        guard advancedSettings.scope == .fixedArea else {
            return startAdvancedMode(advancedSettings, area: nil)
        }
        AreaPicker.pick(showsCursor: settings.captureCursor) { [weak self] area in
            // Cancelling the selection simply doesn't start the session — no alert.
            guard let self, let area else { return }
            self.startAdvancedMode(advancedSettings, area: area)
        }
    }

    private func startAdvancedMode(_ advancedSettings: AdvancedModeSettings, area: CGRect?) {
        let ownHotkeys = [settings.captureHotkey, settings.advancedModeHotkey] + [advancedSettings.stepHotkey].compactMap { $0 }
        switch advancedMode.start(settings: advancedSettings, area: area, ownWindowIDs: currentOwnWindowIDs(),
                                  ignoredKeys: ownHotkeys) {
        case .started:
            statusItemController.setAdvancedModeActive(true)
            showAdvancedModePanel()
            if advancedMode.typingUnavailable {
                advancedModePanel?.state.warning = "Typing not recorded — grant Input Monitoring"
                advancedModePanel?.fitContent()
            }
            registerStepHotkey(advancedSettings.stepHotkey)
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
        }
    }

    /// Only while a session runs, so the combination stays free for other apps the rest of the time.
    private func registerStepHotkey(_ binding: HotkeyBinding?) {
        guard let binding else { return }
        if !hotkeyManager.register(binding, id: HotkeyID.advancedModeStep.rawValue, handler: { [weak self] in
            self?.advancedMode.captureManualStep()
        }) {
            NSLog("Clipr: step hotkey \(binding.displayString) unavailable for this session")
        }
    }

    private func unregisterStepHotkey() {
        hotkeyManager.unregister(id: HotkeyID.advancedModeStep.rawValue)
    }

    private func showAdvancedModePanel() {
        let panel = AdvancedModeControlPanel(
            onTogglePause: { [weak self] in self?.toggleAdvancedModePause() },
            onStop: { [weak self] in self?.toggleAdvancedMode() }
        )
        panel.orderFrontRegardless()
        advancedModePanel = panel
    }

    private func hideAdvancedModePanel() {
        advancedModePanel?.orderOut(nil)
        advancedModePanel = nil
    }

    private func toggleAdvancedModePause() {
        let paused = advancedMode.togglePause()
        advancedModePanel?.state.isPaused = paused
        statusItemController.setAdvancedModeStepCount(advancedModePanel?.state.stepCount ?? 0, paused: paused)
    }

    private func reviewLastSession() {
        if let review = advancedMode.reviewLastSession() {
            review.present()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "No Advanced Mode Sessions"
        alert.informativeText = "Sessions recorded with Advanced Mode will show up here once they've captured at least one step."
        alert.runModal()
    }

    private func currentOwnWindowIDs() -> Set<CGWindowID> {
        windowIDs(of: [statusItemController.statusItem.button?.window, preferencesWindowController?.window]
            + openEditors.map { $0.window }
            + advancedMode.reviewWindows
            + [advancedModePanel])
    }

    /// Clicking the Dock icon with no windows open used to do nothing. Bring back an editor that's
    /// still around (e.g. miniaturized), otherwise open Preferences — the one window Clipr can
    /// always show, and the place to find the capture shortcut.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else { return true }
        if let editor = frontmostEditor() {
            editor.window?.deminiaturize(nil)
            bringToFront(editor)
        } else {
            openPreferences()
        }
        return false
    }

    /// Quitting abandons every editor's pending 800ms auto-save debounce (and each Review's 0.5s
    /// caption debounce), so the last edit in each open window would be lost silently. Flushing
    /// here writes them synchronously first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for editor in openEditors {
            editor.flushPendingSave()
        }
        advancedMode.flushOpenReviews()
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
            bringToFront(existing)
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
            onCaptureCursorChanged: { [weak self] in self?.applyCaptureCursorSetting() },
            // Clipr's own hotkeys are off while a shortcut is being recorded, so pressing the
            // current capture combo records it instead of taking a screenshot.
            onHotkeyRecording: { [weak self] recording in
                guard let self else { return }
                if recording {
                    self.hotkeyManager.unregister(id: HotkeyID.capture.rawValue)
                    self.hotkeyManager.unregister(id: HotkeyID.advancedMode.rawValue)
                } else {
                    self.registerHotkeys()
                }
            }
        )
        preferencesWindowController = controller
        // Cleared on close so the next Preferences request builds a fresh window rather than
        // trying to reuse a closed one.
        if let window = controller.window {
            let box = ObserverTokenBox()
            box.token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                self?.preferencesWindowController = nil
                if let token = box.token { NotificationCenter.default.removeObserver(token) }
            }
        }
        bringToFront(controller)
    }

    /// Clipr is a menu-bar app, so it usually isn't active when Preferences is chosen; showing the
    /// window without activating first left it behind whatever app the user was in. Activate,
    /// then order front explicitly — `showWindow` alone doesn't raise a window of an inactive app.
    private func bringToFront(_ controller: NSWindowController) {
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        controller.window?.orderFrontRegardless()
    }

    /// `CaptureManager`/`AdvancedModeCoordinator` each hold their own `captureCursor` copy rather
    /// than reading `SettingsStore` live, so both need re-syncing here — at launch, and again
    /// whenever the Preferences toggle changes.
    private func applyCaptureCursorSetting() {
        captureManager.captureCursor = settings.captureCursor
        advancedMode.captureCursor = settings.captureCursor
    }
}

/// Holds a notification observer's token so the observer's own closure can remove it.
private final class ObserverTokenBox: @unchecked Sendable {
    var token: NSObjectProtocol?
}
