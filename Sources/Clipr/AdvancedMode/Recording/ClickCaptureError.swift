enum ClickCaptureError: Error {
    case accessibilityNotGranted
    /// `CGEvent.tapCreate` returned nil despite Accessibility being granted — seen with ad-hoc
    /// signed builds after a re-sign. Reported rather than swallowed, since the session would
    /// otherwise appear to start and then record nothing.
    case eventTapCreationFailed
}
