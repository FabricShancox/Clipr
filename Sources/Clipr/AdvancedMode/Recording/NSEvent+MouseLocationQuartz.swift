import Cocoa

extension NSEvent {
    /// `NSEvent.mouseLocation` is AppKit space; steps work in Quartz global space.
    static var mouseLocationQuartz: CGPoint {
        let p = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}
