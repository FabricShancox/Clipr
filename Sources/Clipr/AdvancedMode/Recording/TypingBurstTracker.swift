import Foundation

/// Groups an Advanced Mode session's key presses into typing bursts (via `KeystrokeAggregator`),
/// ends a burst after `KeystrokeAggregator.idleTimeout` of quiet, and reads the focused field as
/// the burst's keys arrive so a text step can be checked against the field it went into.
final class TypingBurstTracker {
    /// The focused field at a text burst's first and latest accepted printable key. Both `nil` for
    /// a shortcut.
    struct FieldReads {
        let start: Task<FocusedField, Never>?
        let last: Task<FocusedField, Never>?
    }

    private var keystrokes = KeystrokeAggregator()
    /// The focused field at the current burst's first accepted printable key.
    private var burstStartField: Task<FocusedField, Never>?
    /// The focused field at the burst's latest accepted printable key. Each read is chained after
    /// the previous one so the answers arrive in key order.
    private var burstLastField: Task<FocusedField, Never>?
    private var idleWork: DispatchWorkItem?
    private let readFocusedField: () async -> FocusedField

    /// A finished burst or shortcut, with the field reads that go with it.
    var onTyped: (TypingEvent, FieldReads) -> Void = { _, _ in }

    init(readFocusedField: @escaping () async -> FocusedField) {
        self.readFocusedField = readFocusedField
    }

    /// Forgets the previous session's burst and field reads.
    func reset() {
        keystrokes = KeystrokeAggregator()
        burstStartField = nil
        burstLastField = nil
    }

    func handle(_ key: KeyInput) {
        let before = keystrokes.bufferedCharacterCount
        for typed in keystrokes.handle(key, at: Date()) { emit(typed) }
        // Only a key the burst actually took as text reads the focused field — not arrows,
        // Escape, shortcuts or the Return/Tab that ends a burst.
        if keystrokes.bufferedCharacterCount > before { readField(startsBurst: before == 0) }
        scheduleIdleCheck()
    }

    func endBurst() {
        idleWork?.cancel()
        if let typed = keystrokes.endBurst() { emit(typed) }
    }

    func cancelIdleCheck() {
        idleWork?.cancel()
    }

    /// Throws a half-typed burst away instead of emitting it.
    func discard() {
        idleWork?.cancel()
        idleWork = nil
        keystrokes = KeystrokeAggregator()
        burstStartField = nil
        burstLastField = nil
    }

    /// Read at the key, not at the end of the burst: by the time a Tab or click ends the burst
    /// it has already reached the app, so a read then would usually see the next field and the
    /// step would be dropped as a focus change.
    private func readField(startsBurst: Bool) {
        let previous = burstLastField
        let read = Task { _ = await previous?.value; return await self.readFocusedField() }
        if startsBurst { burstStartField = read }
        burstLastField = read
    }

    private func scheduleIdleCheck() {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let typed = self.keystrokes.idleCheck(now: Date()) else { return }
            self.emit(typed)
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + KeystrokeAggregator.idleTimeout, execute: work)
    }

    private func emit(_ typed: TypingEvent) {
        switch typed {
        case .shortcut:
            onTyped(typed, FieldReads(start: nil, last: nil))
        case .text:
            let reads = FieldReads(start: burstStartField, last: burstLastField)
            burstStartField = nil
            burstLastField = nil
            onTyped(typed, reads)
        }
    }
}
