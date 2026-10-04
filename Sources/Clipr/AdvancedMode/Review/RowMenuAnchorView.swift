import AppKit
import SwiftUI

/// A plain, non-control view placed in a button's `.background`; it only records itself.
struct RowMenuAnchorView: NSViewRepresentable {
    let anchor: RowMenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { anchor.view = view }
}
