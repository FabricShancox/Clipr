import AppKit
import SwiftUI

/// One item of a Review row menu, described as data so the menus can be tested and shown as a
/// native `NSMenu` popped up from a SwiftUI-drawn button.
///
/// Why not SwiftUI's `Menu`: on macOS it's an `NSPopUpButton`, and a native control inside a List
/// row sets accessibility attributes while SwiftUI updates the row — re-entering that update and
/// leaving SwiftUI in an attribute cycle it never exits (see the segmented-picker freeze). A menu
/// popped up on demand puts no native control in the row at all.
indirect enum RowMenuEntry {
    case action(String, enabled: Bool = true, checked: Bool = false, perform: () -> Void)
    case submenu(String, enabled: Bool, [RowMenuEntry])
    case separator
}
