import Foundation

/// Thrown by `withTimeout` when the operation doesn't finish in time.
struct TimedOutError: Error, LocalizedError {
    let seconds: Double
    var errorDescription: String? { "The screen couldn't be captured — macOS didn't respond within \(Int(seconds)) seconds." }
}

/// Runs `operation`, but gives up after `seconds`.
///
/// Returns as soon as the deadline passes even if `operation` ignores cancellation — a structured
/// task group would wait for it to finish, which is exactly the hang this exists to escape (a
/// ScreenCaptureKit query that never returns around a permission prompt left every later capture
/// silently ignored until relaunch). The operation is cancelled and its late result dropped.
func withTimeout<T>(_ seconds: Double, _ operation: @escaping () async throws -> T) async throws -> T {
    let gate = ResumeOnce()
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
        let work = Task {
            do {
                let value = try await operation()
                if gate.claim() { continuation.resume(returning: value) }
            } catch {
                if gate.claim() { continuation.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if gate.claim() {
                work.cancel()
                continuation.resume(throwing: TimedOutError(seconds: seconds))
            }
        }
    }
}

/// Lets exactly one of several racers resume a continuation.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
