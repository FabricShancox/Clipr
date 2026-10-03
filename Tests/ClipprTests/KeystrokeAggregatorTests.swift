import XCTest
@testable import Clipr

final class KeystrokeAggregatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)

    private func key(_ c: String, code: UInt16 = 0, mods: KeyModifiers = [], secure: Bool = false) -> KeyInput {
        KeyInput(characters: c, baseCharacters: c.lowercased(), keyCode: code, modifiers: mods, isSecure: secure)
    }

    private func type(_ s: String, into a: inout KeystrokeAggregator) {
        for ch in s { _ = a.handle(key(String(ch)), at: t0) }
    }

    func testIdleEndsBurst() {
        var a = KeystrokeAggregator()
        type("John", into: &a)
        XCTAssertNil(a.idleCheck(now: t0.addingTimeInterval(0.5)))
        XCTAssertEqual(a.idleCheck(now: t0.addingTimeInterval(1.0)), .text("John"))
        XCTAssertFalse(a.hasPendingBurst)
    }

    func testReturnAndTabEndBurst() {
        var a = KeystrokeAggregator()
        type("hi", into: &a)
        XCTAssertEqual(a.handle(key("\r", code: 36), at: t0), [.text("hi")])
        type("yo", into: &a)
        XCTAssertEqual(a.handle(key("\t", code: 48), at: t0), [.text("yo")])
        XCTAssertEqual(a.handle(key("\r", code: 36), at: t0), [])  // empty burst emits nothing
    }

    func testExplicitEndForClick() {
        var a = KeystrokeAggregator()
        type("abc", into: &a)
        XCTAssertEqual(a.endBurst(), .text("abc"))
        XCTAssertNil(a.endBurst())
    }

    func testBackspaceRemovesLastCharacterAndIsSafeWhenEmpty() {
        var a = KeystrokeAggregator()
        _ = a.handle(key("\u{7F}", code: 51), at: t0)
        type("Jonn", into: &a)
        _ = a.handle(key("\u{7F}", code: 51), at: t0)
        XCTAssertEqual(a.endBurst(), .text("Jon"))
    }

    func testArrowsAndEscapeAreIgnored() {
        var a = KeystrokeAggregator()
        type("a", into: &a)
        _ = a.handle(key("\u{F702}", code: 123), at: t0)
        _ = a.handle(key("\u{1B}", code: 53), at: t0)
        XCTAssertEqual(a.endBurst(), .text("a"))
    }

    func testShortcutEndsBurstAndUsesGlyphOrder() {
        var a = KeystrokeAggregator()
        type("x", into: &a)
        let events = a.handle(key("s", mods: [.command, .shift, .control, .option]), at: t0)
        XCTAssertEqual(events, [.text("x"), .shortcut("⌃⌥⇧⌘S")])
    }

    func testShiftAloneIsTyping() {
        var a = KeystrokeAggregator()
        _ = a.handle(key("J", mods: [.shift]), at: t0)
        XCTAssertEqual(a.endBurst(), .text("J"))
    }

    func testSecureBurstIsDiscardedEvenIfLaterKeysAreNotSecure() {
        var a = KeystrokeAggregator()
        _ = a.handle(key("p", secure: true), at: t0)
        _ = a.handle(key("w"), at: t0)
        XCTAssertNil(a.endBurst())
        type("ok", into: &a)   // next burst is clean again
        XCTAssertEqual(a.endBurst(), .text("ok"))
    }

    func testSecureBurstEndedByReturnEmitsNothing() {
        var a = KeystrokeAggregator()
        _ = a.handle(key("p", secure: true), at: t0)
        XCTAssertEqual(a.handle(key("\r", code: 36), at: t0), [])
    }

    func testShortcutKeysUseGlyphNames() {
        // Left arrow: code 123
        var a = KeystrokeAggregator()
        let events = a.handle(key("\u{F702}", code: 123, mods: [.command]), at: t0)
        XCTAssertEqual(events, [.shortcut("⌘←")])
    }

    func testShortcutSpaceUsesCaptionNotWhitespace() {
        // Space: code 49
        var a = KeystrokeAggregator()
        let events = a.handle(key(" ", code: 49, mods: [.command]), at: t0)
        XCTAssertEqual(events, [.shortcut("⌘Space")])
    }

    func testShortcutTabUsesTabulationGlyph() {
        // Tab: code 48
        var a = KeystrokeAggregator()
        let events = a.handle(key("\t", code: 48, mods: [.control]), at: t0)
        XCTAssertEqual(events, [.shortcut("⌃⇥")])
    }

    func testShortcutDeleteUsesDeletionGlyph() {
        // Delete (backspace): code 51
        var a = KeystrokeAggregator()
        let events = a.handle(key("\u{7F}", code: 51, mods: [.command]), at: t0)
        XCTAssertEqual(events, [.shortcut("⌘⌫")])
    }

    func testSecureBurstClearsBuffer() {
        var a = KeystrokeAggregator()
        _ = a.handle(key("a"), at: t0)
        _ = a.handle(key("b"), at: t0)
        _ = a.handle(key("p", secure: true), at: t0)
        // Buffer should be cleared, isSecureBurst true
        _ = a.handle(key("c"), at: t0)
        XCTAssertEqual(a.bufferedCharacterCount, 0)
        XCTAssertNil(a.endBurst())
    }

    func testSecureBurstEndedByIdleEmitsNothing() {
        var a = KeystrokeAggregator()
        _ = a.handle(key("p", secure: true), at: t0)
        XCTAssertNil(a.idleCheck(now: t0.addingTimeInterval(1.0)))
        XCTAssertFalse(a.hasPendingBurst)
    }

    func testCleanBurstAfterSecureEmitsOnlyNewText() {
        var a = KeystrokeAggregator()
        _ = a.handle(key("p", secure: true), at: t0)
        _ = a.handle(key("w"), at: t0)
        XCTAssertNil(a.endBurst())
        type("hello", into: &a)
        XCTAssertEqual(a.endBurst(), .text("hello"))
    }

    func testNonSecureKeysDoNotAccumulateAfterSecureKey() {
        var a = KeystrokeAggregator()
        _ = a.handle(key("p", secure: true), at: t0)
        _ = a.handle(key("a"), at: t0)
        _ = a.handle(key("b"), at: t0)
        // Buffer should be empty even though non-secure keys were typed
        XCTAssertEqual(a.bufferedCharacterCount, 0)
        XCTAssertTrue(a.hasPendingBurst)
        XCTAssertNil(a.endBurst())
    }
}
