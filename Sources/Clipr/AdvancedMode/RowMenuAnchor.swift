import AppKit
import SwiftUI

/// Remembers the AppKit view behind a button's background so a menu can be anchored to it.
@MainActor
final class RowMenuAnchor {
    weak var view: NSView?
}
