import XCTest
@testable import Clipr

/// What the Preferences shortcut recorder does with a key press. A bare letter, Esc or Delete
/// registered as a global hotkey would swallow that key in every app, so a binding needs ⌘, ⌃ or ⌥
/// (⇧ alone isn't enough) — except F1–F20, which nothing types.
final class HotkeyRecordingTests: XCTestCase {
    private let cmd = HotkeyBinding.Modifier.command.rawValue
    private let shift = HotkeyBinding.Modifier.shift.rawValue
    private let opt = HotkeyBinding.Modifier.option.rawValue
    private let ctrl = HotkeyBinding.Modifier.control.rawValue

    private func outcome(_ keyCode: UInt32, _ modifiers: UInt32) -> HotkeyBinding.RecordingOutcome {
        HotkeyBinding.recordingOutcome(keyCode: keyCode, modifiers: modifiers)
    }

    func testAComboAlreadyUsedByAnotherClipShortcutIsRejected() {
        let advanced = HotkeyBinding(keyCode: 1, modifiers: cmd | shift | ctrl)
        let result = HotkeyBinding.recordingOutcome(keyCode: 1, modifiers: cmd | shift | ctrl, takenBy: [(advanced, "Advanced Mode")])
        XCTAssertEqual(result, .rejected("Already used for Advanced Mode"))
        let other = HotkeyBinding.recordingOutcome(keyCode: 2, modifiers: cmd | shift | ctrl, takenBy: [(advanced, "Advanced Mode")])
        XCTAssertEqual(other, .accepted(HotkeyBinding(keyCode: 2, modifiers: cmd | shift | ctrl)))
    }

    func testBareLetterIsRejected() {
        guard case .rejected = outcome(0, 0) else { return XCTFail("bare A accepted") }
    }

    func testShiftAloneIsRejected() {
        guard case .rejected = outcome(0, shift) else { return XCTFail("⇧A accepted") }
    }

    func testBareReturnTabDeleteAreRejected() {
        for key: UInt32 in [36, 48, 51, 117, 49] {
            guard case .rejected = outcome(key, 0) else { return XCTFail("bare key \(key) accepted") }
        }
    }

    func testEscapeCancelsRecording() {
        XCTAssertEqual(outcome(53, 0), .cancelled)
        XCTAssertEqual(outcome(53, shift), .cancelled)
    }

    func testEachOfCommandControlOptionIsEnough() {
        for modifiers in [cmd, ctrl, cmd | shift, ctrl | opt | shift, cmd | opt] {
            XCTAssertEqual(outcome(1, modifiers), .accepted(HotkeyBinding(keyCode: 1, modifiers: modifiers)))
        }
    }

    func testOptionAloneIsRejected() {
        for modifiers in [opt, opt | shift] {
            guard case .rejected = outcome(1, modifiers) else { return XCTFail("⌥-only accepted: \(modifiers)") }
        }
        XCTAssertEqual(outcome(122, opt), .accepted(HotkeyBinding(keyCode: 122, modifiers: opt)), "F-keys stay free")
    }

    func testStandardShortcutsAreAcceptedWithANotice() {
        for key: UInt32 in [12, 13, 4, 46, 48, 49, 43, 8, 9, 7, 6, 0] {
            XCTAssertEqual(outcome(key, cmd), .accepted(HotkeyBinding(keyCode: key, modifiers: cmd)), "key \(key)")
            XCTAssertNotNil(HotkeyBinding.conflictNotice(keyCode: key, modifiers: cmd), "key \(key)")
        }
        XCTAssertEqual(HotkeyBinding.conflictNotice(keyCode: 12, modifiers: cmd), "⌘Q will take a screenshot instead of quitting apps")
        XCTAssertNil(HotkeyBinding.conflictNotice(keyCode: 12, modifiers: cmd | shift))
        XCTAssertNil(HotkeyBinding.conflictNotice(keyCode: 1, modifiers: cmd))
    }

    func testBareFunctionKeysF1ThroughF20AreAllowed() {
        let fKeys: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                               105, 107, 113, 106, 64, 79, 80, 90]
        for key in fKeys {
            XCTAssertEqual(outcome(key, 0), .accepted(HotkeyBinding(keyCode: key, modifiers: 0)), "F-key \(key)")
            XCTAssertEqual(outcome(key, shift), .accepted(HotkeyBinding(keyCode: key, modifiers: shift)))
        }
    }

    func testRejectionCarriesAShortHint() {
        guard case .rejected(let hint) = outcome(0, 0) else { return XCTFail() }
        XCTAssertFalse(hint.isEmpty)
        XCTAssertLessThan(hint.count, 60)
    }
}
