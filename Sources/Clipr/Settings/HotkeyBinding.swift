import Carbon
import Foundation

struct HotkeyBinding: Codable, Equatable {
    enum Modifier: UInt32 {
        case command = 256  // Carbon cmdKey (bit 8)
        case shift = 512    // Carbon shiftKey (bit 9)
        case option = 2048  // Carbon optionKey (bit 11)
        case control = 4096 // Carbon controlKey (bit 12)
    }

    let keyCode: UInt32
    let modifiers: UInt32

    // Keys that don't type a printable character, so the keyboard layout can't name them.
    private static let specialKeyNames: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦", 76: "⌤",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"
    ]

    /// The key's label, e.g. "Q" or "F5". Printable keys are named through the current keyboard
    /// layout rather than a fixed table, so the label matches what's printed on the user's keycap
    /// (a German layout's Z/Y swap, AZERTY, and so on).
    static func keyName(for keyCode: UInt32) -> String {
        if let name = specialKeyNames[keyCode] { return name }
        return layoutCharacter(for: keyCode)?.uppercased() ?? "?"
    }

    private static func layoutCharacter(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: chars, count: length)
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : string
    }

    var displayString: String {
        var s = ""
        if modifiers & Modifier.command.rawValue != 0 { s += "⌘" }
        if modifiers & Modifier.shift.rawValue != 0 { s += "⇧" }
        if modifiers & Modifier.option.rawValue != 0 { s += "⌥" }
        if modifiers & Modifier.control.rawValue != 0 { s += "⌃" }
        s += HotkeyBinding.keyName(for: keyCode)
        return s
    }

    /// F1–F20. The only keys allowed as a hotkey without ⌘/⌃/⌥, since nothing types them.
    static let functionKeyCodes: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
        105, 107, 113, 106, 64, 79, 80, 90
    ]
    static let escapeKeyCode: UInt32 = 53

    /// What the Preferences shortcut recorder should do with a key press.
    enum RecordingOutcome: Equatable {
        case accepted(HotkeyBinding)
        /// Esc (without ⌘/⌃/⌥): stop recording and keep the current binding.
        case cancelled
        /// Not usable as a global hotkey; the string is a short hint to show the user.
        case rejected(String)
    }

    /// A global hotkey swallows its key in every app, so a bare letter, Return, Delete or Esc
    /// bound here would stop that key working system-wide. A binding therefore needs ⌘, ⌃ or ⌥
    /// (⇧ alone still types a character), except F1–F20, which may be bare.
    static func recordingOutcome(keyCode: UInt32, modifiers: UInt32) -> RecordingOutcome {
        let required = Modifier.command.rawValue | Modifier.control.rawValue | Modifier.option.rawValue
        let hasRequired = modifiers & required != 0
        if keyCode == escapeKeyCode, !hasRequired { return .cancelled }
        if hasRequired || functionKeyCodes.contains(keyCode) {
            return .accepted(HotkeyBinding(keyCode: keyCode, modifiers: modifiers))
        }
        return .rejected("Include ⌘, ⌃ or ⌥ (or use F1–F20)")
    }

    static let defaultCapture = HotkeyBinding(keyCode: 19, modifiers: Modifier.command.rawValue | Modifier.shift.rawValue) // ⌘⇧2
    static let defaultAdvancedMode = HotkeyBinding(keyCode: 20, modifiers: Modifier.command.rawValue | Modifier.shift.rawValue) // ⌘⇧3
}
