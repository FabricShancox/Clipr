import Foundation

/// The ⌃⌥⇧⌘ modifiers held for a key press.
struct KeyModifiers: OptionSet, Equatable {
    let rawValue: Int
    static let control = KeyModifiers(rawValue: 1 << 0)
    static let option = KeyModifiers(rawValue: 1 << 1)
    static let shift = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)
}
