import Cocoa

/// Owns the click-capture lifecycle and the Review windows it opens, so `AppDelegate` only has
/// to decide what UI to show for each outcome (status item state, alerts) rather than also
/// tracking window bookkeeping itself.
final class AdvancedModeCoordinator {
    private let clickCaptureManager: ClickCaptureManager
    private let storage: StorageManager
    private var openReviewWindows: [ReviewWindowController] = []
    var onStepCaptured: ((Int) -> Void)?

    init(storage: StorageManager) {
        self.storage = storage
        clickCaptureManager = ClickCaptureManager(storage: storage)
        clickCaptureManager.onStepCaptured = { [weak self] count in self?.onStepCaptured?(count) }
    }

    var isPaused: Bool { clickCaptureManager.isPaused }

    /// Returns the new paused state.
    @discardableResult
    func togglePause() -> Bool {
        guard clickCaptureManager.isActive else { return false }
        clickCaptureManager.isPaused.toggle()
        return clickCaptureManager.isPaused
    }

    var captureCursor: Bool {
        get { clickCaptureManager.captureCursor }
        set { clickCaptureManager.captureCursor = newValue }
    }

    /// Windows of any still-open Review sessions — folded into `AppDelegate.currentOwnWindowIDs`
    /// so Advanced Mode never captures its own Review window as if it were a step.
    var reviewWindows: [NSWindow?] { openReviewWindows.map(\.window) }

    enum StartOutcome {
        case started
        case accessibilityNotGranted
        case startFailed(Error)
    }

    var isActive: Bool { clickCaptureManager.isActive }
    var typingUnavailable: Bool { clickCaptureManager.typingUnavailable }

    /// Main thread only: `ownWindowIDs` is read by the live image source on the main actor.
    func start(settings: AdvancedModeSettings, area: CGRect?, ownWindowIDs: Set<CGWindowID>) -> StartOutcome {
        clickCaptureManager.ownWindowIDs = ownWindowIDs
        do {
            _ = try clickCaptureManager.start(settings: settings, area: area)
            return .started
        } catch ClickCaptureError.accessibilityNotGranted {
            return .accessibilityNotGranted
        } catch {
            return .startFailed(error)
        }
    }

    /// `nil` when the session captured nothing; its empty folder is removed so "Review Last
    /// Session" never lands on it.
    func stop(completion: @escaping (ReviewWindowController?) -> Void) {
        clickCaptureManager.stop { [weak self] manifest, folder in
            guard let self, let folder else { return completion(nil) }
            guard let manifest, !manifest.steps.isEmpty else {
                try? FileManager.default.removeItem(at: folder)
                return completion(nil)
            }
            completion(self.openReview(manifest: manifest, sessionFolder: folder))
        }
    }

    func captureManualStep() { clickCaptureManager.captureManualStep() }

    /// The most recent session's steps, read back from disk so it works after a relaunch too.
    /// `nil` when there's no session folder with any steps in it.
    func reviewLastSession() -> ReviewWindowController? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: storage.baseFolder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return nil }
        // Session folder names embed a sortable `yyyy-MM-dd_HHmmss` timestamp, so name order is
        // chronological order.
        let sessions = entries
            .filter { $0.lastPathComponent.hasPrefix("Session_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for folder in sessions {
            let manifest = SessionManifestStore.load(from: folder)
            if !manifest.steps.isEmpty { return openReview(manifest: manifest, sessionFolder: folder) }
        }
        return nil
    }

    private func openReview(manifest: SessionManifest, sessionFolder: URL) -> ReviewWindowController {
        let review = ReviewWindowController(manifest: manifest, sessionFolder: sessionFolder, storage: storage)
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
        return review
    }
}
