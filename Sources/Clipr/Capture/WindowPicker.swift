import Cocoa

struct WindowInfo: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let bounds: CGRect
    let layer: Int
}

struct WindowPicker {
    /// CGWindowListCopyWindowInfo already returns windows front-to-back;
    /// both pure lookups below rely on that ordering rather than re-sorting by layer,
    /// since layer alone doesn't disambiguate windows within the same layer.
    static func onScreenWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { entry -> WindowInfo? in
            guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID,
                  let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = entry[kCGWindowLayer as String] as? Int else {
                return nil
            }
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            return WindowInfo(windowID: windowID, ownerPID: ownerPID, bounds: bounds, layer: layer)
        }
    }

    static func window(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.bounds.contains(point) }
    }

    static func frontmostWindow(ownedBy pid: pid_t, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.ownerPID == pid }
    }
}
