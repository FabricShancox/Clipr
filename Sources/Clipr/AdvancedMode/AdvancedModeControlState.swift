import SwiftUI

/// Observable state the floating control panel renders — owned by `AdvancedModeControlPanel` and
/// updated by `AdvancedModeController` as steps land and the session pauses/resumes.
final class AdvancedModeControlState: ObservableObject {
    @Published var stepCount = 0
    @Published var isPaused = false
    /// One-line notice under the controls, e.g. typing is off because Input Monitoring is denied.
    @Published var warning: String?
    /// One-line notice that a step or session.json couldn't be saved; see `StepSaveProblem`.
    @Published var saveWarning: String?
}
