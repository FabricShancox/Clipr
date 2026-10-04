/// Why a recorded step didn't fully land — see `ClickCaptureManager.onSaveProblem`.
enum StepSaveProblem: Equatable {
    /// The step's image couldn't be written; the step is skipped and its number reused.
    case stepDropped
    /// session.json couldn't be updated; the next step's save retries it.
    case manifestNotSaved
}
