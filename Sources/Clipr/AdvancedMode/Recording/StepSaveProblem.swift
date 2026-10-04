/// Why a recorded step didn't fully land — see `ClickCaptureManager.onSaveProblem`.
enum StepSaveProblem: Equatable {
    /// The step's image couldn't be written; the step is skipped and its number reused.
    case stepDropped
    /// A slow double-click's replacement couldn't be written; the earlier version of the step was kept.
    case stepNotUpdated
    /// session.json couldn't be updated; the next step's save retries it.
    case manifestNotSaved
}
