import AppKit

/// The focused text field as read for a typing step: its label, security and on-screen frame.
struct FocusedField {
    var label: String?
    var security: FieldSecurity
    /// `nil` when there's no focused element (security is then `unknown`), and in test fakes.
    var element: AXUIElement?
    /// Where the element is on screen (Quartz global, top-left origin), so a typing step can
    /// capture the display the typing happened on. `nil` when Accessibility can't say.
    var frame: CGRect? = nil
}
