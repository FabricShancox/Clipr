import Cocoa
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    let statusItemController = StatusItemController()
    let settings = SettingsStore()
    // Installs a process-wide Carbon event handler in its init with no teardown logic, so it
    // must live for the whole process lifetime as a plain stored property.
    let hotkeyManager = HotkeyManager()
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
        NSApp.setActivationPolicy(.accessory)

        applyCaptureCursorSetting()

        captureManager.onCaptureFinished = { [weak self] rawURL, image in
            self?.openEditor(image: image, rawURL: rawURL)
        }
        advancedMode.onStepCaptured = { [weak self] count in
            self?.statusItemController.setAdvancedModeStepCount(count)
        }

        statusItemController.onCaptureNow = { [weak self] in self?.performCapture() }
        statusItemController.onOpenImage = { [weak self] in self?.openImage() }
        statusItemController.onToggleAdvancedMode = { [weak self] in self?.toggleAdvancedMode() }
        statusItemController.onOpenPreferences = { [weak self] in self?.openPreferences() }

        registerHotkeys()
    }

    private func openEditor(image: NSImage, rawURL: URL) {
        let editor = EditorWindowController(image: image, rawURL: rawURL, storage: storage)
        openEditors.append(editor)
        editor.onFinished = { [weak self, weak editor] in
            guard let self, let editor else { return }
            self.openEditors.removeAll { $0 === editor }
        }
        editor.showWindow(nil)
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
        hotkeyManager.register(settings.captureHotkey, id: HotkeyID.capture.rawValue) { [weak self] in
            self?.performCapture()
        }
        hotkeyManager.register(settings.advancedModeHotkey, id: HotkeyID.advancedMode.rawValue) { [weak self] in
            self?.toggleAdvancedMode()
        }
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
            NSLog("Clipr: failed to start advanced mode: \(error)")
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

    private func openPreferences() {
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
