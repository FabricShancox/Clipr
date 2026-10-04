import CoreGraphics

/// An input event an Advanced Mode session reacts to.
enum SessionEvent: Equatable {
    /// `clickCount` is the system's click state: 2 for the second press of a double-click.
    /// `window` is what was under the click when it happened.
    case click(CGPoint, clickCount: Int = 1, window: ClickedWindow? = nil)
    /// A click on Clipr itself (menu-bar icon, control panel). Never a step, but it still ends a
    /// typing burst so text typed just before pressing Stop isn't lost.
    case ownClick
    case mouseMoved(CGPoint)
    case key(KeyInput)
}
