import Foundation

struct KeyModifiers: OptionSet, Equatable {
    let rawValue: Int
    static let control = KeyModifiers(rawValue: 1 << 0)
    static let option = KeyModifiers(rawValue: 1 << 1)
    static let shift = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)
}

/// One key press, already decoded off the event tap so this file stays free of CGEvent.
struct KeyInput: Equatable {
    /// As typed (with Shift/Option applied).
    var characters: String
    /// `charactersIgnoringModifiers`, used to name shortcuts.
    var baseCharacters: String
    var keyCode: UInt16
    var modifiers: KeyModifiers
    /// macOS secure input was on, or the focused element is a password field.
    var isSecure: Bool
}

enum TypingEvent: Equatable {
    case text(String)
    case shortcut(String)
}

/// Groups key presses into "typed X" bursts and "pressed ⌘S" shortcuts for typing steps.
/// Time is passed in rather than read, so the idle rule is testable.
struct KeystrokeAggregator {
    static let idleTimeout: TimeInterval = 1.0

    private enum KeyCode {
        static let returnKey: UInt16 = 36, keypadEnter: UInt16 = 76, tab: UInt16 = 48
        static let delete: UInt16 = 51, escape: UInt16 = 53, forwardDelete: UInt16 = 117
        static let space: UInt16 = 49
        static let arrows: ClosedRange<UInt16> = 123...126
        static let left: UInt16 = 123, right: UInt16 = 124, down: UInt16 = 125, up: UInt16 = 126

        /// Map keyCode to glyph/name for shortcuts. Keys not in this map use baseCharacters.uppercased().
        static let nameMap: [UInt16: String] = [
            returnKey: "↩",
            keypadEnter: "⌤",
            tab: "⇥",
            space: "Space",
            delete: "⌫",
            forwardDelete: "⌦",
            escape: "⎋",
            left: "←",
            right: "→",
            down: "↓",
            up: "↑"
        ]
    }

    private var buffer = ""
    /// Once any key of a burst was secure the whole burst is thrown away — even characters typed
    /// before secure input switched on — so no fragment of a password can ever be stored.
    private var isSecureBurst = false
    private var lastKeyAt: Date?

    var hasPendingBurst: Bool { !buffer.isEmpty || isSecureBurst }

    /// For tests to verify secure input doesn't retain plaintext in the buffer.
    var bufferedCharacterCount: Int { buffer.count }

    mutating func handle(_ key: KeyInput, at time: Date) -> [TypingEvent] {
        if key.modifiers.contains(.command) || key.modifiers.contains(.control) {
            var events: [TypingEvent] = []
            if let ended = endBurst() { events.append(ended) }
            let keyName = KeyCode.nameMap[key.keyCode] ?? key.baseCharacters.uppercased()
            events.append(.shortcut(Self.glyphs(key.modifiers) + keyName))
            return events
        }
        switch key.keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter, KeyCode.tab:
            return endBurst().map { [$0] } ?? []
        case KeyCode.escape, KeyCode.forwardDelete, KeyCode.arrows:
            return []
        default:
            break
        }
        lastKeyAt = time
        if key.isSecure || isSecureBurst {
            isSecureBurst = true
            buffer = ""
            return []
        }
        if key.keyCode == KeyCode.delete {
            if !buffer.isEmpty { buffer.removeLast() }
            return []
        }
        buffer += key.characters.filter(Self.isPrintable)
        return []
    }

    mutating func endBurst() -> TypingEvent? {
        defer { buffer = ""; isSecureBurst = false; lastKeyAt = nil }
        guard !isSecureBurst, !buffer.isEmpty else { return nil }
        return .text(buffer)
    }

    mutating func idleCheck(now: Date) -> TypingEvent? {
        guard let lastKeyAt, now.timeIntervalSince(lastKeyAt) >= Self.idleTimeout else { return nil }
        return endBurst()
    }

    private static func glyphs(_ m: KeyModifiers) -> String {
        (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "")
            + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "")
    }

    /// Excludes control characters and the private-use range (U+F700–U+F8FF) AppKit uses for
    /// function and arrow keys.
    private static func isPrintable(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }
    }
}
