import Foundation

/// Orders an Advanced Mode session's step writes. Captures run concurrently, but every step awaits
/// the one before it before writing, so steps land in the order the user did them even when a slow
/// capture finishes after a fast one.
final class StepWriteChain {
    /// A place in the chain reserved when the user clicked, not when the delayed capture fires —
    /// otherwise a typing burst that ends inside the click's delay (e.g. on Stop) would be written
    /// before the click that came first.
    struct Slot {
        let predecessor: Task<Void, Never>?
        let done: AsyncStream<Void>.Continuation
    }

    /// The tail of the chain. `ClickCaptureManager.stop` awaits this to know everything is on disk.
    private(set) var tail: Task<Void, Never>?

    func reset() {
        tail = nil
    }

    /// Appends a placeholder to the chain that completes when the slot's `done` is finished.
    func reserve() -> Slot {
        let (stream, done) = AsyncStream<Void>.makeStream()
        let predecessor = tail
        // Waits for its predecessor too, so finishing a superseded click's slot early can't
        // let later steps (or `stop`) skip past a step that's still capturing.
        tail = Task {
            for await _ in stream {}
            await predecessor?.value
        }
        return Slot(predecessor: predecessor, done: done)
    }

    /// What a new step waits for: its reserved slot's place, or else the end of the chain.
    func predecessor(for slot: Slot?) -> Task<Void, Never>? {
        slot.map(\.predecessor) ?? tail
    }

    /// A step with a reserved slot is already in the chain; any other joins at the end.
    func append(_ task: Task<Void, Never>, reserved slot: Slot?) {
        if slot == nil { tail = task }
    }
}
