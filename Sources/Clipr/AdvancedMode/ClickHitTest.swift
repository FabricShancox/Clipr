import Cocoa

/// What a click hit, from the on-screen window list (front to back).
enum ClickHitTest: Equatable {
    /// One of Clipr's own windows: the menu-bar icon, the control panel, Review, an editor.
    case own
    case other(ClickedWindow?)

    /// Pure, for tests: `entries` as `CGWindowListCopyWindowInfo` returns them.
    static func resolve(_ point: CGPoint, in entries: [[String: Any]], ownPID: pid_t,
                        appName: (pid_t) -> String? = { _ in nil }) -> ClickHitTest {
        for entry in entries {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            if let alpha = entry[kCGWindowAlpha as String] as? CGFloat, alpha == 0 { continue }
            let bounds = CGRect(x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                                width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0)
            guard bounds.contains(point) else { continue }
            if ownerPID == ownPID { return .own }
            guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID else { return .other(nil) }
            let layer = entry[kCGWindowLayer as String] as? Int ?? 0
            let name = appName(ownerPID) ?? entry[kCGWindowOwnerName as String] as? String
            return .other(ClickedWindow(windowID: windowID, ownerPID: ownerPID, layer: layer, appName: name))
        }
        return .other(nil)
    }

    /// Thread-safe; the event tap calls it off the main thread.
    static func live(_ point: CGPoint) -> ClickHitTest {
        let entries = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return resolve(point, in: entries, ownPID: ProcessInfo.processInfo.processIdentifier) {
            NSRunningApplication(processIdentifier: $0)?.localizedName
        }
    }
}
