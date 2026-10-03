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

        let sessionFolder = clickCaptureManager.currentSessionFolder
        let stepURLs = clickCaptureManager.stop()
        guard !stepURLs.isEmpty else {
            // Nothing to keep — don't leave an empty Session folder behind to be picked up by
            // "Review Last Session".
            if let sessionFolder,
               (try? FileManager.default.contentsOfDirectory(atPath: sessionFolder.path))?.isEmpty == true {
                try? FileManager.default.removeItem(at: sessionFolder)
            }
            return .stoppedNoSteps
        }
        return .stopped(openReview(stepURLs: stepURLs, sessionFolder: sessionFolder))
    }

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
            let steps = Self.stepURLs(in: folder)
            if !steps.isEmpty { return openReview(stepURLs: steps, sessionFolder: folder) }
        }
        return nil
    }

    private static func stepURLs(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files
            // Raw steps only — the editor writes `_edited.png` previews alongside them.
            .filter { $0.lastPathComponent.hasPrefix("Step_") && $0.pathExtension.lowercased() == "png"
                && !$0.lastPathComponent.hasSuffix("_edited.png") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func openReview(stepURLs: [URL], sessionFolder: URL?) -> ReviewWindowController {
        let review = ReviewWindowController(stepURLs: stepURLs, sessionFolder: sessionFolder, storage: storage)
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
