import Cocoa

/// Owns the click-capture lifecycle and the Review windows it opens, so `AppDelegate` only has
/// to decide what UI to show for each outcome (status item state, alerts) rather than also
/// tracking window bookkeeping itself.
final class AdvancedModeCoordinator {
    enum ToggleOutcome {
        case started
        case accessibilityNotGranted
        case startFailed(Error)
        case stoppedNoSteps
        case stopped(ReviewWindowController)
    }

    private let clickCaptureManager: ClickCaptureManager
    private let storage: StorageManager
    private var openReviewWindows: [ReviewWindowController] = []
    var onStepCaptured: ((Int) -> Void)?

    init(storage: StorageManager) {
        self.storage = storage
        clickCaptureManager = ClickCaptureManager(storage: storage)
        clickCaptureManager.onStepCaptured = { [weak self] count in self?.onStepCaptured?(count) }
    }

    var captureCursor: Bool {
        get { clickCaptureManager.captureCursor }
        set { clickCaptureManager.captureCursor = newValue }
    }

    /// Windows of any still-open Review sessions — folded into `AppDelegate.currentOwnWindowIDs`
    /// so Advanced Mode never captures its own Review window as if it were a step.
    var reviewWindows: [NSWindow?] { openReviewWindows.map(\.window) }

    /// `ownWindowIDs` is `@autoclosure` since it's only needed when starting (self-exclusion),
    /// not when stopping — avoids computing it pointlessly on every stop.
    func toggle(ownWindowIDs: @autoclosure () -> Set<CGWindowID>) -> ToggleOutcome {
        guard clickCaptureManager.isActive else {
            clickCaptureManager.ownWindowIDs = ownWindowIDs()
            do {
                _ = try clickCaptureManager.start()
                return .started
            } catch ClickCaptureError.accessibilityNotGranted {
                return .accessibilityNotGranted
            } catch {
                return .startFailed(error)
            }
        }

        let stepURLs = clickCaptureManager.stop()
        guard !stepURLs.isEmpty else { return .stoppedNoSteps }

        let review = ReviewWindowController(stepURLs: stepURLs, storage: storage)
        openReviewWindows.append(review)
        // ReviewWindowController has no onFinished-style closure (unlike EditorWindowController),
        // so its close is observed externally via NSWindow.willCloseNotification instead.
        if let window = review.window {
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self, weak review] _ in
                guard let self, let review else { return }
                self.openReviewWindows.removeAll { $0 === review }
            }
        }
        return .stopped(review)
    }
}
