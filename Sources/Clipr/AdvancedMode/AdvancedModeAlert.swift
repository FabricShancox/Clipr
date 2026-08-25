import Cocoa

/// Advanced Mode captures the frontmost app window on every click — it has no drag-to-select-an-
/// area interaction, and clicking somewhere with no real window under the cursor (e.g. the
/// Desktop) captures nothing. Naming the actual interaction model here is cheaper than a UI
/// redesign.
func showNoStepsCapturedAlert() {
    let alert = NSAlert()
    alert.messageText = "No Steps Captured"
    alert.informativeText = "Advanced Mode captures the frontmost app window each time you click it — not a dragged area. Click inside a real app window (not the empty Desktop) to record a step."
    alert.runModal()
}
