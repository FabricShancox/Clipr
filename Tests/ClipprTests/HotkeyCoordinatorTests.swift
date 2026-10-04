import XCTest
@testable import Clipr

/// Pausing Clipr's hotkeys while Preferences records a shortcut, and reporting refusals once.
@MainActor
final class HotkeyCoordinatorTests: XCTestCase {
    private final class FakeRegistry: HotkeyRegistering {
        var registered: [UInt32: HotkeyBinding] = [:]
        var refused: [HotkeyBinding] = []
        func register(_ binding: HotkeyBinding, id: UInt32, handler: @escaping () -> Void) -> Bool {
            registered[id] = nil
            guard !refused.contains(binding) else { return false }
            registered[id] = binding
            return true
        }
        func unregister(id: UInt32) { registered[id] = nil }
    }

    private var defaults: UserDefaults!
    private var settings: SettingsStore!
    private var registry: FakeRegistry!
    private var alerts: [String] = []
    private var coordinator: HotkeyCoordinator!
    private let step = HotkeyBinding(keyCode: 1, modifiers: HotkeyBinding.Modifier.control.rawValue)

    override func setUp() {
        super.setUp()
        let suite = "HotkeyCoordinatorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        settings = SettingsStore(defaults: defaults)
        registry = FakeRegistry()
        alerts = []
        coordinator = HotkeyCoordinator(manager: registry, settings: settings) { [unowned self] title, _ in
            alerts.append(title)
        }
        coordinator.registerAppHotkeys()
    }

    private var ids: Set<UInt32> { Set(registry.registered.keys) }

    func testSwitchingRecordersKeepsHotkeysPaused() {
        coordinator.registerStepHotkey(step) {}
        XCTAssertEqual(ids, [1, 2, 3])
        coordinator.setRecording(true, recorder: "a")
        XCTAssertEqual(ids, [], "the step hotkey pauses too")
        coordinator.setRecording(true, recorder: "b")
        coordinator.setRecording(false, recorder: "a") // late end of the first recorder
        XCTAssertEqual(ids, [], "still recording in b")
        coordinator.reregisterAppHotkeys()
        XCTAssertEqual(ids, [], "a binding change mid-record waits for the end")
        coordinator.setRecording(false, recorder: "b")
        XCTAssertEqual(ids, [1, 2, 3])
    }

    func testEndAllRecordingResumes() {
        coordinator.setRecording(true, recorder: "a")
        XCTAssertEqual(ids, [])
        coordinator.endAllRecording()
        XCTAssertEqual(ids, [1, 2])
        coordinator.setRecording(false, recorder: "a")
        XCTAssertEqual(ids, [1, 2])
    }

    func testStepHotkeyRegisteredWhilePausedWaitsForResume() {
        coordinator.setRecording(true, recorder: "a")
        coordinator.registerStepHotkey(step) {}
        XCTAssertEqual(ids, [])
        coordinator.setRecording(false, recorder: "a")
        XCTAssertEqual(ids, [1, 2, 3])
        coordinator.unregisterStepHotkey()
        coordinator.setRecording(true, recorder: "a")
        coordinator.setRecording(false, recorder: "a")
        XCTAssertEqual(ids, [1, 2], "an ended session's step hotkey doesn't come back")
    }
}
