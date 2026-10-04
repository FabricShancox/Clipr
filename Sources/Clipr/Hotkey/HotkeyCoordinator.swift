import Cocoa

/// What `HotkeyCoordinator` needs from the system hotkey registry — `HotkeyManager` in the app, a
/// fake in tests.
protocol HotkeyRegistering: AnyObject {
    @discardableResult
    func register(_ binding: HotkeyBinding, id: UInt32, handler: @escaping () -> Void) -> Bool
    func unregister(id: UInt32)
}

extension HotkeyManager: HotkeyRegistering {}

/// Registers Clipr's global hotkeys from `SettingsStore` and tells the user when one is refused.
///
/// The capture and Advanced Mode hotkeys live for the whole app session; the step hotkey is only
/// registered while an Advanced Mode session runs, so the combination stays free for other apps
/// the rest of the time.
@MainActor
final class HotkeyCoordinator {
    enum HotkeyID: UInt32 {
        case capture = 1
        case advancedMode = 2
        case advancedModeStep = 3
    }

    private let hotkeyManager: HotkeyRegistering
    private let settings: SettingsStore
    private let showAlert: (_ title: String, _ detail: String) -> Void

    var onCapture: () -> Void = {}
    var onToggleAdvancedMode: () -> Void = {}

    /// Shortcut recorders currently recording. Hotkeys stay off while any of them is, so moving
    /// straight from one recorder to another (the first one's end arrives after the second began)
    /// can't switch them back on mid-record.
    private var activeRecorders: Set<AnyHashable> = []
    /// The step hotkey the running session asked for, kept so it can come back after recording.
    private var stepRegistration: (binding: HotkeyBinding, handler: () -> Void)?

    var isPausedForRecording: Bool { !activeRecorders.isEmpty }

    init(manager: HotkeyRegistering, settings: SettingsStore,
         showAlert: @escaping (_ title: String, _ detail: String) -> Void = { title, detail in
             Alerts.run(title, detail)
         }) {
        self.hotkeyManager = manager
        self.settings = settings
        self.showAlert = showAlert
    }

    func registerAppHotkeys() {
        guard !isPausedForRecording else { return }
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
        showAlert(rejected.count == 1 ? "A shortcut couldn't be registered" : "Some shortcuts couldn't be registered", """
            \(rejected.joined(separator: "\n"))

            Another app or macOS is probably already using \(rejected.count == 1 ? "it" : "them"). \
            Pick a different combination in Preferences.
            """)
    }

    func unregisterAppHotkeys() {
        hotkeyManager.unregister(id: HotkeyID.capture.rawValue)
        hotkeyManager.unregister(id: HotkeyID.advancedMode.rawValue)
    }

    /// Re-reads both bindings after Preferences changed them. While a recorder is still recording
    /// this waits: the bindings are re-read when recording ends.
    func reregisterAppHotkeys() {
        guard !isPausedForRecording else { return }
        unregisterAppHotkeys()
        registerAppHotkeys()
    }

    /// Clipr's own hotkeys (step hotkey included) are off while a shortcut is being recorded, so
    /// pressing the current capture combo records it instead of taking a screenshot. `recorder`
    /// identifies the recorder; hotkeys come back only once no recorder is recording.
    func setRecording(_ recording: Bool, recorder: AnyHashable) {
        let wasPaused = isPausedForRecording
        if recording {
            activeRecorders.insert(recorder)
        } else {
            activeRecorders.remove(recorder)
        }
        if !wasPaused && isPausedForRecording {
            unregisterAppHotkeys()
            hotkeyManager.unregister(id: HotkeyID.advancedModeStep.rawValue)
        } else if wasPaused && !isPausedForRecording {
            resumeAfterRecording()
        }
    }

    /// Preferences closed: whatever recorder state is left over, hotkeys come back.
    func endAllRecording() {
        guard isPausedForRecording else { return }
        activeRecorders.removeAll()
        resumeAfterRecording()
    }

    private func resumeAfterRecording() {
        unregisterAppHotkeys()
        registerAppHotkeys()
        if let stepRegistration {
            registerStep(stepRegistration.binding, handler: stepRegistration.handler)
        }
    }

    /// Only while a session runs, so the combination stays free for other apps the rest of the time.
    func registerStepHotkey(_ binding: HotkeyBinding?, handler: @escaping () -> Void) {
        guard let binding else { return }
        stepRegistration = (binding, handler)
        guard !isPausedForRecording else { return }
        registerStep(binding, handler: handler)
    }

    private func registerStep(_ binding: HotkeyBinding, handler: @escaping () -> Void) {
        if !hotkeyManager.register(binding, id: HotkeyID.advancedModeStep.rawValue, handler: handler) {
            NSLog("Clipr: step hotkey \(binding.displayString) unavailable for this session")
        }
    }

    func unregisterStepHotkey() {
        stepRegistration = nil
        hotkeyManager.unregister(id: HotkeyID.advancedModeStep.rawValue)
    }
}
