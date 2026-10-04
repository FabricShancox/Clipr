import Foundation

/// Races a task against a timeout.
enum TaskTimeout {
    /// `task`'s value, or `nil` if it takes longer than `timeout` — a slow AX read falls back to
    /// the generic caption instead of holding the step back, and a hung capture can't hold up
    /// `stop` forever. A race of two unstructured tasks
    /// rather than a task group: a group waits for every child before returning, and awaiting
    /// `task.value` ignores cancellation, so a group would never actually cut a slow read short.
    static func value<T>(of task: Task<T, Never>?, timeout: TimeInterval) async -> T? {
        guard let task else { return nil }
        return await withCheckedContinuation { continuation in
            let first = FirstResult()
            Task {
                let value = await task.value
                if first.claim() { continuation.resume(returning: .some(value)) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if first.claim() { continuation.resume(returning: nil) }
            }
        }
    }
}

/// Lets exactly one of two racing tasks resume a continuation.
private final class FirstResult: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}
