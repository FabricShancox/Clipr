import Cocoa

/// Starts, pauses and stops Advanced Mode sessions from the app's menu and hotkeys, and shows the
/// floating Pause/Stop bar while one runs. `AdvancedModeCoordinator` does the capturing and owns
/// the Review windows; this is the app-facing side: permissions, area picking, the step hotkey,
/// the status item and the alerts.
@MainActor
final class AdvancedModeController {
    private let coordinator: AdvancedModeCoordinator
    private let settings: SettingsStore
    private let statusItemController: StatusItemController
    private let hotkeys: HotkeyCoordinator
    /// Clipr's windows outside Advanced Mode (status item, Preferences, editors), kept out of
    /// every step capture.
    var otherOwnWindows: () -> [NSWindow?] = { [] }
    /// The floating Pause/Stop bar — present only while an Advanced Mode session runs.
    private var panel: AdvancedModeControlPanel?

    init(coordinator: AdvancedModeCoordinator, settings: SettingsStore,
         statusItemController: StatusItemController, hotkeys: HotkeyCoordinator) {
        self.coordinator = coordinator
        self.settings = settings
        self.statusItemController = statusItemController
        self.hotkeys = hotkeys
        coordinator.onStepCaptured = { [weak self] count in
            self?.statusItemController.setAdvancedModeStepCount(count)
            self?.panel?.state.stepCount = count
        }
    }

    func toggle() {
        if coordinator.isActive {
            hotkeys.unregisterStepHotkey()
            coordinator.stop { [weak self] review in
                guard let self else { return }
                self.statusItemController.setAdvancedModeActive(false)
                self.hidePanel()
                if let review {
                    review.present()
                } else {
                    Alerts.noStepsCaptured()
                }
            }
            return
        }
        // Starting puts up an area picker or a recording session over whatever's open; with a
        // modal dialog up that leaves it unreachable. Stopping (above) is always allowed.
        guard !ModalHotkeyGuard.shouldIgnoreNow() else { NSSound.beep(); return }
        let advancedSettings = settings.advancedMode
        guard advancedSettings.scope == .fixedArea else {
            return start(advancedSettings, area: nil)
        }
        AreaPicker.pick(showsCursor: settings.captureCursor) { [weak self] area in
            // Cancelling the selection simply doesn't start the session — no alert.
            guard let self, let area else { return }
            self.start(advancedSettings, area: area)
        }
    }

    func reviewLastSession() {
        if let review = coordinator.reviewLastSession() {
            review.present()
            return
        }
        Alerts.run("No Advanced Mode Sessions",
                   "Sessions recorded with Advanced Mode will show up here once they've captured at least one step.",
                   activate: true)
    }

    private func start(_ advancedSettings: AdvancedModeSettings, area: CGRect?) {
        let ownHotkeys = [settings.captureHotkey, settings.advancedModeHotkey] + [advancedSettings.stepHotkey].compactMap { $0 }
        switch coordinator.start(settings: advancedSettings, area: area, ownWindowIDs: currentOwnWindowIDs(),
                                 ignoredKeys: ownHotkeys) {
        case .started:
            statusItemController.setAdvancedModeActive(true)
            showPanel()
            if coordinator.typingUnavailable {
                panel?.state.warning = "Typing not recorded — grant Input Monitoring"
                panel?.fitContent()
            }
            hotkeys.registerStepHotkey(advancedSettings.stepHotkey) { [weak self] in
                self?.coordinator.captureManualStep()
            }
        case .accessibilityNotGranted:
            Alerts.permissionRequired(pane: .accessibility, message: "Clipr needs Accessibility access to detect clicks for Advanced Mode.")
        case .startFailed(let error):
            // Surfaced, not just logged: the user asked for this and nothing visible would
            // happen otherwise — the menu would simply stay on "Start Advanced Mode".
            NSLog("Clipr: failed to start advanced mode: \(error)")
            Alerts.run("Couldn't start Advanced Mode", error.localizedDescription)
        }
    }

    private func showPanel() {
        let panel = AdvancedModeControlPanel(
            onTogglePause: { [weak self] in self?.togglePause() },
            onStop: { [weak self] in self?.toggle() }
        )
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func togglePause() {
        let paused = coordinator.togglePause()
        panel?.state.isPaused = paused
        statusItemController.setAdvancedModeStepCount(panel?.state.stepCount ?? 0, paused: paused)
    }

    private func currentOwnWindowIDs() -> Set<CGWindowID> {
        windowIDs(of: otherOwnWindows() + coordinator.reviewWindows + [panel])
    }
}
