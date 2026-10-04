import Foundation

/// When the system disables the tap, whether and when to turn it back on, and what to log.
/// A timeout (the callback was slow) is re-armed at once, as is standard. A disable caused by user
/// input is the system's own signal, so it's logged and re-armed only after a pause instead of
/// fighting the system in a loop. Logging is rate-limited so a tap that keeps timing out can't
/// flood the log.
struct TapRearmPolicy {
    enum Action: Equatable {
        case rearmNow
        case rearmAfter(TimeInterval)
    }

    static let userInputBackoff: TimeInterval = 1
    private(set) var timeouts = 0
    private(set) var userInputDisables = 0

    mutating func handleDisable(byUserInput: Bool) -> (action: Action, log: String?) {
        if byUserInput {
            userInputDisables += 1
            let log = Self.shouldLog(userInputDisables)
                ? "Clipr: advanced mode event tap was disabled by user input (\(userInputDisables)x); re-arming in \(Self.userInputBackoff) s"
                : nil
            return (.rearmAfter(Self.userInputBackoff), log)
        }
        timeouts += 1
        let log = Self.shouldLog(timeouts)
            ? "Clipr: advanced mode event tap timed out (\(timeouts)x); re-enabled"
            : nil
        return (.rearmNow, log)
    }

    /// The first time, then every tenth.
    private static func shouldLog(_ count: Int) -> Bool { count == 1 || count % 10 == 0 }
}
