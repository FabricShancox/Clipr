import Cocoa

/// Extracts `CGWindowID`s from a list of (possibly-absent) windows — used by `AdvancedModeController` to
/// build the self-exclusion set Advanced Mode checks each click against, so Clipr never captures
/// its own menu bar, Preferences, editor, or Review windows as if they were a step the user
/// clicked through.
func windowIDs(of windows: [NSWindow?]) -> Set<CGWindowID> {
    var ids: Set<CGWindowID> = []
    for window in windows {
        if let number = window?.windowNumber, let id = CGWindowID(exactly: number) {
            ids.insert(id)
        }
    }
    return ids
}
