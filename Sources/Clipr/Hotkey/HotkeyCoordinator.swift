import Cocoa

/// Registers Clipr's global hotkeys from `SettingsStore` and tells the user when one is refused.
///
/// The capture and Advanced Mode hotkeys live for the whole app session; the step hotkey is only
/// registered while an Advanced Mode session runs, so the combination stays free for other apps
/// the rest of the time.
@MainActor
final class HotkeyCoordinator {
    private enum HotkeyID: UInt32 {
        case capture = 1
        case advancedMode = 2
        case advancedModeStep = 3
    }

    private let hotkeyManager: HotkeyManager
    private let settings: SettingsStore

    var onCapture: () -> Void = {}
    var onToggleAdvancedMode: () -> Void = {}

    init(manager: HotkeyManager, settings: SettingsStore) {
        self.hotkeyManager = manager
        self.settings = settings
    }

    func registerAppHotkeys() {
        var rejected: [String] = []
        if !hotkeyManager.register(settings.captureHotkey, id: HotkeyID.capture.rawValue, handler: { [weak self] in
            self?.onCapture()
        }) {
            rejected.append("\(settings.captureHotkey.displayString) (Capture)")
        }
        if !hotkeyManager.register(settings.advancedModeHotkey, id: HotkeyID.advancedMode.rawValue, handler: { [weak self] in
            self?.onToggleAdvancedMode()
        }) {
            rejected.append("\(settings.advancedModeHotkey.displayString) (Advanced Mode)")
        }
        guard !rejected.isEmpty else { return }

        // The registration that failed has already dropped whatever was bound before, so staying
        // quiet would leave the user with a hotkey that simply stopped working and no clue why.
        Alerts.run(rejected.count == 1 ? "A shortcut couldn't be registered" : "Some shortcuts couldn't be registered", """
            \(rejected.joined(separator: "\n"))

            Another app or macOS is probably already using \(rejected.count == 1 ? "it" : "them"). \
            Pick a different combination in Preferences.
            """)
    }

    func unregisterAppHotkeys() {
        hotkeyManager.unregister(id: HotkeyID.capture.rawValue)
        hotkeyManager.unregister(id: HotkeyID.advancedMode.rawValue)
    }

    /// Re-reads both bindings after Preferences changed them.
    func reregisterAppHotkeys() {
        unregisterAppHotkeys()
        registerAppHotkeys()
    }

    /// Clipr's own hotkeys are off while a shortcut is being recorded, so pressing the current
    /// capture combo records it instead of taking a screenshot.
    func setRecording(_ recording: Bool) {
        if recording {
            unregisterAppHotkeys()
        } else {
            registerAppHotkeys()
        }
    }

    /// Only while a session runs, so the combination stays free for other apps the rest of the time.
    func registerStepHotkey(_ binding: HotkeyBinding?, handler: @escaping () -> Void) {
        guard let binding else { return }
        if !hotkeyManager.register(binding, id: HotkeyID.advancedModeStep.rawValue, handler: handler) {
            NSLog("Clipr: step hotkey \(binding.displayString) unavailable for this session")
        }
    }

    func unregisterStepHotkey() {
        hotkeyManager.unregister(id: HotkeyID.advancedModeStep.rawValue)
    }
}
