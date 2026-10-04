import Cocoa

/// What an Advanced Mode step captures.
enum CaptureTarget: Equatable {
    case frontmostWindow
    /// The window that was clicked; the frontmost app's window if it has closed since.
    case window(ClickedWindow)
    case screenContaining(CGPoint)
    case area(CGRect)
}

extension CaptureTarget {
    /// The target for a step in `scope`. Window scope captures the window that was clicked, when
    /// it's an app window; a click on the Dock, the menu bar, a pop-up menu or the desktop falls
    /// back to the frontmost app's window.
    static func forScope(_ scope: AdvancedModeSettings.Scope, click: CGPoint?, window: ClickedWindow?, area: CGRect?) -> CaptureTarget {
        switch scope {
        case .window:
            if let window, window.isCapturable { return .window(window) }
            return .frontmostWindow
        case .screen:
            return .screenContaining(click ?? NSEvent.mouseLocationQuartz)
        case .fixedArea:
            return area.map { .area($0) } ?? .frontmostWindow
        }
    }
}
