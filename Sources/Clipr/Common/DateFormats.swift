import Foundation

/// Fixed-pattern date strings (file names, guide dates) from cached `DateFormatter`s, which are
/// costly to build. Always `en_US_POSIX`, so the output never follows the user's locale.
/// `DateFormatter` is thread-safe for formatting; the cache itself is behind a lock.
enum DateFormats {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    /// `date` in `pattern` (a `dateFormat` string) at `timeZone`. `gregorian` pins the calendar
    /// rather than leaving it to the locale's default.
    static func string(_ date: Date, pattern: String, timeZone: TimeZone = .current, gregorian: Bool = false) -> String {
        formatter(pattern: pattern, timeZone: timeZone, gregorian: gregorian).string(from: date)
    }

    private static func formatter(pattern: String, timeZone: TimeZone, gregorian: Bool) -> DateFormatter {
        let key = "\(pattern)|\(timeZone.identifier)|\(gregorian)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if gregorian { formatter.calendar = Calendar(identifier: .gregorian) }
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        cache[key] = formatter
        return formatter
    }
}
