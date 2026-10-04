import Cocoa

/// Owns the click-capture lifecycle and the Review windows it opens, so `AdvancedModeController` only has
/// to decide what UI to show for each outcome (status item state, alerts) rather than also
/// tracking window bookkeeping itself.
final class AdvancedModeCoordinator {
    private let clickCaptureManager: ClickCaptureManager
    private let storage: StorageManager
    private var openReviewWindows: [ReviewWindowController] = []
    /// Image editors opened from Review, per session folder (standardized path). They outlive the
    /// Review that opened them, so a reopened Review knows about them and quit still flushes them.
    private var editorRegistries: [String: SessionEditorRegistry] = [:]
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

    /// Windows of any still-open Review sessions — folded into `AdvancedModeController.currentOwnWindowIDs`
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
    func start(settings: AdvancedModeSettings, area: CGRect?, ownWindowIDs: Set<CGWindowID>,
               ignoredKeys: [HotkeyBinding]) -> StartOutcome {
        clickCaptureManager.ownWindowIDs = ownWindowIDs
        do {
            _ = try clickCaptureManager.start(settings: settings, area: area, ignoredKeys: ignoredKeys)
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
            completion(self.openReview(sessionFolder: folder))
        }
    }

    /// Quit while recording: finishes the session (pending click, typing burst, in-flight writes
    /// and session.json) within `timeout`, without opening Review.
    func stopForQuit(timeout: TimeInterval, completion: @escaping () -> Void) {
        guard clickCaptureManager.isActive else { return completion() }
        clickCaptureManager.stop(flushTimeout: timeout) { manifest, folder in
            if let folder, manifest?.steps.isEmpty ?? true {
                try? FileManager.default.removeItem(at: folder)
            }
            completion()
        }
    }

    func captureManualStep() { clickCaptureManager.captureManualStep() }

    /// The most recent session's steps, read back from disk so it works after a relaunch too.
    /// `nil` when there's no session folder with any steps in it other than the one being recorded.
    func reviewLastSession() -> ReviewWindowController? {
        // Reviewing the session being recorded would let its edits race the capture's own writes
        // to session.json.
        let active = clickCaptureManager.isActive ? clickCaptureManager.currentSessionFolder : nil
        guard let folder = Self.latestSessionWithSteps(in: storage.baseFolder, excluding: active) else { return nil }
        return openReview(sessionFolder: folder)
    }

    /// Newest `Session_` folder under `base` with at least one step, skipping `excluded`.
    static func latestSessionWithSteps(in base: URL, excluding excluded: URL?) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return nil }
        // Session folder names embed a sortable `yyyy-MM-dd_HHmmss` timestamp, so name order is
        // chronological order. Compared numerically: a same-second session gets `_2`, `_3` … and
        // `_10` must sort after `_9`.
        let sessions = entries
            .filter { $0.lastPathComponent.hasPrefix("Session_") }
            .filter { excluded == nil || !sameFolder($0, excluded!) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
        return sessions.first { !SessionManifestStore.load(from: $0).steps.isEmpty }
    }

    /// Runs a capture for Review's "Retake Screenshot…" and hands back the image. Set by
    /// `AppDelegate`, which owns the capture manager.
    var captureReplacement: ((@escaping (NSImage?) -> Void) -> Void)?

    /// Writes every open Review's pending caption (and its editors' pending saves) now. Quit calls
    /// this: termination doesn't close windows, so their close-time flush would never run.
    func flushOpenReviews() {
        for review in openReviewWindows { review.flush() }
        // Editors whose Review was closed.
        for registry in editorRegistries.values { registry.flushAll() }
    }

    /// The editor registry for `sessionFolder`, created on first use. Registries with no editors
    /// left are dropped along the way.
    func editorRegistry(for sessionFolder: URL) -> SessionEditorRegistry {
        editorRegistries = editorRegistries.filter { !$0.value.isEmpty }
        let key = Self.folderKey(sessionFolder)
        if let existing = editorRegistries[key] { return existing }
        let registry = SessionEditorRegistry()
        editorRegistries[key] = registry
        return registry
    }

    /// Reuses the Review already open for `sessionFolder`, if any: two windows on one session
    /// would each save their own copy of the manifest over the other's edits.
    func openReview(sessionFolder: URL) -> ReviewWindowController {
        if let existing = openReviewWindows.first(where: { Self.sameFolder($0.sessionFolder, sessionFolder) }) {
            return existing
        }
        // The coordinator is only ever called on the main thread.
        let review = MainActor.assumeIsolated { ReviewWindowController(
            sessionFolder: sessionFolder, storage: storage,
            editors: editorRegistry(for: sessionFolder),
            captureReplacement: { [weak self] done in
                guard let capture = self?.captureReplacement else { return done(nil) }
                capture(done)
            }
        ) }
        openReviewWindows.append(review)
        // ReviewWindowController has no onFinished-style closure (unlike EditorWindowController),
        // so its close is observed externally via NSWindow.willCloseNotification instead.
        // The observer removes itself, so closing Reviews doesn't leave one behind per window.
        if let window = review.window {
            let observer = ReviewCloseObserver()
            observer.token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self, weak review] _ in
                if let token = observer.token { NotificationCenter.default.removeObserver(token) }
                guard let self, let review else { return }
                self.openReviewWindows.removeAll { $0 === review }
            }
        }
        return review
    }

    private static func sameFolder(_ a: URL, _ b: URL) -> Bool {
        folderKey(a) == folderKey(b)
    }

    private static func folderKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// Holds a notification observer's token so the observer's own closure can remove it.
private final class ReviewCloseObserver: @unchecked Sendable {
    var token: NSObjectProtocol?
}
