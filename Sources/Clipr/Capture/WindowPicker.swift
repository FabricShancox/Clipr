import Cocoa

struct WindowPicker {
    /// CGWindowListCopyWindowInfo already returns windows front-to-back;
    /// both pure lookups below rely on that ordering rather than re-sorting by layer,
    /// since layer alone doesn't disambiguate windows within the same layer.
    ///
    /// Two categories of window are filtered out here, at the single source every lookup below
    /// shares, so that both `window(at:in:)` and `frontmostWindow(ownedBy:in:)` are protected:
    ///
    /// 1. Clipr's own windows (`ownerPID` equal to this process's own pid). During Window-mode
    ///    selection the `CaptureOverlayWindow` is a full-screen `.screenSaver`-level window
    ///    covering every display, so it would otherwise sit ahead of every real user window in
    ///    front-to-back order and `window(at:)` would resolve *every* hover/click to that overlay.
    /// 2. Windows outside the normal window layer (`layer != 0`). Ordinary application windows -
    ///    the only things a user means to capture - live on layer 0; the Dock, the menu bar,
    ///    system chrome, and floating/screen-saver-level panels (Clipr's overlay included) all
    ///    sit on higher layers. This is a superset of the self-exclusion above for the overlay
    ///    specifically, but each check catches cases the other doesn't (a normal-layer Clipr
    ///    window such as Preferences or the editor; another app's floating panel), so both stay.
    ///
    /// Note this filter deliberately does NOT depend on any caller-supplied pid: normal windows of
    /// every *other* process still pass through, which is what `frontmostWindow(ownedBy:in:)`
    /// needs in order to find the frontmost window of whichever app the user clicked in.
    static func onScreenWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { entry -> WindowInfo? in
            guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID,
                  let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat],
                  let layer = entry[kCGWindowLayer as String] as? Int else {
                return nil
            }
            guard ownerPID != ownPID, layer == 0 else { return nil }
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            return WindowInfo(windowID: windowID, ownerPID: ownerPID, bounds: bounds, layer: layer)
        }
    }

    /// Owner of the topmost on-screen window at `point` (global, top-left-origin coordinates — the
    /// same space as `CGEvent.location`), across every layer and every process. Unlike
    /// `onScreenWindows()` this keeps Clipr's own and non-normal-layer windows, since its job is
    /// telling Advanced Mode a click landed on Clipr itself (its menu-bar icon, its control panel).
    static func ownerPIDOfWindow(at point: CGPoint) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for entry in list {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            if let alpha = entry[kCGWindowAlpha as String] as? CGFloat, alpha == 0 { continue }
            let bounds = CGRect(
                x: boundsDict["X"] ?? 0,
                y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0,
                height: boundsDict["Height"] ?? 0
            )
            if bounds.contains(point) { return ownerPID }
        }
        return nil
    }

    static func window(at point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.bounds.contains(point) }
    }

    static func frontmostWindow(ownedBy pid: pid_t, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.ownerPID == pid }
    }
}
