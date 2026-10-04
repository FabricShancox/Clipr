import Foundation

/// What `KeystrokeAggregator` emits: a typed burst or a shortcut.
enum TypingEvent: Equatable {
    case text(String)
    case shortcut(String)
}
