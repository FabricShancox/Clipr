import AppKit

/// Reads, via Accessibility, what was clicked and which field has focus; faked in tests.
protocol ClickDescribing: AnyObject {
    /// What's under `point` (Quartz global). `nil` if Accessibility can't say.
    func describe(at point: CGPoint) async -> ClickTarget?
    /// The focused element's label (for "Type … in **Name**"), whether it's a password field,
    /// and the element itself so a burst can be checked to start and end in the same field.
    func focusedField() async -> FocusedField
}
