import Cocoa

/// The window a click landed on, resolved when the click happens: by the time a delayed capture
/// runs, the click may have opened a new window in front, or closed the menu that was clicked.
struct ClickedWindow: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let layer: Int
    /// The owning app's name, for the caption ("Click **Save** in Pages").
    let appName: String?

    /// Ordinary windows, floating palettes, panels and utility windows: what a Window-scope step
    /// should show. The Dock, the menu bar, pop-up menus and the desktop are not — a click there
    /// is captured as before, from the frontmost app's window.
    var isCapturable: Bool { layer >= 0 && layer < Self.dockLayer }

    static let dockLayer = Int(CGWindowLevelForKey(.dockWindow))
}

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
