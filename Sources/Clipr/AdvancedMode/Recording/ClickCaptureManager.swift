import Cocoa

/// Runs one Advanced Mode session: turns tap events into steps according to the settings
/// snapshot taken at `start`, and writes each step as PNG → annotations sidecar → zoom →
/// `session.json`, in that order, so the manifest never names a file that isn't on disk.
///
/// Step creation lives in `ClickCaptureManager+Steps`, and preparing and writing a step's files in
/// `ClickCaptureManager+StepFiles`.
final class ClickCaptureManager {
    private let storage: StorageManager
    private let imageSource: StepImageSource
    private let describer: ClickDescribing
    private let eventSource: SessionEventSource
    private let accessibilityGranted: () -> Bool
    private let inputMonitoringGranted: () -> Bool

    private var sessionFolder: URL?
    private var manifest: SessionManifest?
    private(set) var settings = AdvancedModeSettings.default
    private(set) var area: CGRect?
    private var nextStepIndex = 1
    private var trail = CursorTrailRecorder()
    private let typing: TypingBurstTracker
    /// Clipr's own hotkeys. The listen-only tap sees their keyDown before Carbon dispatches them,
    /// so without this every press would also become a "Press ⌘⇧2" typing step.
    private var ignoredKeys: [HotkeyBinding] = []
    private var pending: PendingClick?
    private let writes = StepWriteChain()
    private var isStopping = false
    /// Where the user last clicked: the best guess at the display a shortcut was pressed on.
    private(set) var lastClickPoint: CGPoint?

    private static let stopFlushTimeout: TimeInterval = 10

    /// Pausing discards a half-typed burst rather than writing it, so nothing lands while paused.
    /// A click still inside its delay is captured now, showing the screen it was made on rather
    /// than whatever the user does while paused. The cursor trail is dropped both ways, so
    /// movement from before a pause never leads into the first click after it.
    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            _ = trail.drain()
            guard isPaused else { return }
            typing.discard()
            if let pending {
                pending.work.cancel()
                self.pending = nil
                fire(pending)
            }
        }
    }
    var captureCursor = false
    /// Every display's frame (Quartz global), read on the main actor when a Screen-scope typing
    /// step picks its display. Replaced in tests.
    var screenFrames: @MainActor () -> [CGRect] = { ClickCaptureManager.quartzScreenFrames() }
    private(set) var typingUnavailable = false
    var onStepCaptured: ((Int) -> Void)?

    var isActive: Bool { sessionFolder != nil }
    var currentSessionFolder: URL? { sessionFolder }
    var ownWindowIDs: Set<CGWindowID> {
        get { imageSource.ownWindowIDs }
        set { imageSource.ownWindowIDs = newValue }
    }

    struct PendingClick {
        let point: CGPoint
        /// What was under the click when it happened.
        let window: ClickedWindow?
        let trail: [CGPoint]
        let describe: Task<ClickTarget?, Never>?
        let work: DispatchWorkItem
        let slot: StepWriteChain.Slot
    }

    init(
        storage: StorageManager,
        imageSource: StepImageSource = LiveStepImageSource(),
        describer: ClickDescribing = ClickDescriber(),
        eventSource: SessionEventSource = SessionEventTap(),
        accessibilityGranted: @escaping () -> Bool = PermissionsManager.hasAccessibilityPermission,
        inputMonitoringGranted: @escaping () -> Bool = { CGPreflightListenEventAccess() }
    ) {
        self.storage = storage
        self.imageSource = imageSource
        self.describer = describer
        self.eventSource = eventSource
        self.accessibilityGranted = accessibilityGranted
        self.inputMonitoringGranted = inputMonitoringGranted
        self.typing = TypingBurstTracker(readFocusedField: { [describer] in await describer.focusedField() })
        typing.onTyped = { [weak self] in self?.emit($0, fields: $1) }
        eventSource.onEvent = { [weak self] in self?.handle($0) }
    }

    // MARK: Lifecycle

    func start(settings: AdvancedModeSettings, area: CGRect?, ignoredKeys: [HotkeyBinding] = []) throws -> URL {
        guard accessibilityGranted() else {
            PermissionsManager.requestAccessibilityPermission()
            throw ClickCaptureError.accessibilityNotGranted
        }
        let now = Date()
        let folder = try SessionFolder.create(in: storage.baseFolder, date: now)
        self.settings = settings
        self.area = area
        typingUnavailable = settings.typingSteps && !inputMonitoringGranted()
        manifest = SessionManifest(createdAt: now)
        nextStepIndex = 1
        lastClickPoint = nil
        trail = CursorTrailRecorder()
        typing.reset()
        self.ignoredKeys = ignoredKeys
        writes.reset()
        isPaused = false
        // Before `sessionFolder` is set, so a failure can't leave `isActive` true with no tap.
        // The folder is still empty then; removed so "Review Last Session" never lands on it.
        do {
            try eventSource.start(options: SessionEventOptions(
                mouseMoves: settings.cursorTrail,
                keys: settings.typingSteps && !typingUnavailable
            ))
        } catch {
            manifest = nil
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        sessionFolder = folder
        return folder
    }

    /// Stops listening, then finishes what the user already did — a click still inside its
    /// delay, a half-typed burst — and waits for every in-flight capture to be written before
    /// reporting, so the Review window never opens on a session that's still changing.
    /// A second call while that flush is under way is ignored (the first call's completion
    /// reports the session), so a double-click on Stop can't open Review twice.
    func stop(completion: @escaping (SessionManifest?, URL?) -> Void) {
        guard let folder = sessionFolder else { return completion(nil, nil) }
        guard !isStopping else { return }
        isStopping = true
        eventSource.stop()
        if let pending { pending.work.cancel(); fire(pending) }
        pending = nil
        typing.endBurst()
        typing.cancelIdleCheck()
        let last = writes.tail
        Task { @MainActor in
            // Capped so a hung ScreenCaptureKit call can't leave Stop dead forever. On timeout
            // the session completes with what's written so far; `write` drops any late step
            // because the manifest and session folder are cleared below.
            if let last, await TaskTimeout.value(of: last, timeout: Self.stopFlushTimeout) == nil {
                NSLog("Clipr: advanced mode stop gave up waiting for in-flight steps")
            }
            let final = self.manifest
            self.sessionFolder = nil
            self.manifest = nil
            self.writes.reset()
            self.isPaused = false
            self.isStopping = false
            completion(final, folder)
        }
    }

    func captureManualStep() {
        guard isActive, !isPaused, !isStopping else { return }
        _ = trail.drain()
        enqueue(kind: .manual, target: scopeTarget(for: nil), click: nil, trail: [], caption: { _ in nil })
    }

    // MARK: Events

    func handle(_ event: SessionEvent) {
        guard isActive, !isPaused, !isStopping else { return }
        switch event {
        case .mouseMoved(let p):
            if settings.cursorTrail { trail.add(p) }
        case .ownClick:
            typing.endBurst()
        case .click(let p, let clickCount, let window):
            typing.endBurst()
            lastClickPoint = p
            var points = trail.drain()
            if let previous = pending {
                previous.work.cancel()
                pending = nil
                if Self.isRepeatClick(clickCount: clickCount, at: p, after: previous.point) {
                    // The second press of a double-click replaces the first; its trail is kept
                    // so the path still starts where the user began. Its write slot is released
                    // and a fresh one taken below, after any typing burst this click just ended,
                    // so that typing is written before the click.
                    previous.describe?.cancel()
                    previous.slot.done.finish()
                    points = previous.trail + points
                } else {
                    // A click on something else (a checkbox, then OK) is a step of its own:
                    // capture the earlier one now rather than lose it.
                    fire(previous)
                }
            }
            let slot = writes.reserve()
            let describe = settings.autoCaptions ? Task { await self.describer.describe(at: p) } : nil
            let work = DispatchWorkItem { [weak self] in
                guard let self, let pending = self.pending else { return }
                self.pending = nil
                self.fire(pending)
            }
            pending = PendingClick(point: p, window: window, trail: points, describe: describe, work: work, slot: slot)
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.effectiveDelay, execute: work)
        case .key(let key):
            guard settings.typingSteps, !typingUnavailable, !isFrontmostClipr(),
                  !ignoredKeys.contains(where: { $0.matches(key) }) else { return }
            typing.handle(key)
        }
    }

    /// Points a double-click's second press may drift from the first and still be the same click.
    static let doubleClickSlop: CGFloat = 6

    /// The second press of a double-click (or triple-click) on the same spot, as opposed to a
    /// quick click on another control.
    static func isRepeatClick(clickCount: Int, at point: CGPoint, after previous: CGPoint) -> Bool {
        clickCount > 1 && hypot(point.x - previous.x, point.y - previous.y) <= doubleClickSlop
    }

    // MARK: Write chain

    /// `slot` is the click's reserved place in the chain; every other step joins at the end now.
    func enqueue(
        kind: StepRecord.Kind, target: CaptureTarget, resolveTarget: (() async -> CaptureTarget)? = nil,
        click: CGPoint?, appName: String? = nil, trail: [CGPoint],
        slot: StepWriteChain.Slot? = nil,
        skipIf: @escaping () async -> Bool = { false }, caption: @escaping (_ appName: String?) async -> String?
    ) {
        guard let folder = sessionFolder else {
            slot?.done.finish()
            return
        }
        let predecessor = writes.predecessor(for: slot)
        let settings = self.settings
        let showsCursor = captureCursor
        let imageSource = self.imageSource
        // Runs off the main thread, where the event tap lives: capture, PNG encode, zoom crop and
        // every file write happen here. Only claiming the step number and appending to the
        // manifest hop to the main actor, so steps still land in order.
        let task = Task.detached { [weak self] in
            // Released however this step ends — written, skipped or failed — so the steps
            // queued behind it are never stuck waiting.
            defer { slot?.done.finish() }
            // Encoded before waiting for the steps ahead, so a queue of fast clicks holds PNG
            // bytes rather than full-resolution bitmaps.
            let prepared = await Self.captureAndPrepare(
                target: target, resolveTarget: resolveTarget, imageSource: imageSource, showsCursor: showsCursor, skipIf: skipIf,
                kind: kind, click: click, appName: appName, trail: trail, settings: settings, caption: caption
            )
            await predecessor?.value
            guard let self, let prepared else { return }
            await self.write(prepared, folder: folder)
        }
        writes.append(task, reserved: slot)
    }

    /// Called from the write chain, so only one step is ever in here at a time. The step number
    /// is claimed and the manifest appended on the main actor; the files are written off it.
    private func write(_ step: PreparedStep, folder: URL) async {
        // The folder check drops a step from a session that already stopped (its flush timed
        // out) and would otherwise land in the next session's manifest.
        let claimed: Int? = await MainActor.run {
            guard self.manifest != nil, folder == self.sessionFolder else { return nil }
            defer { self.nextStepIndex += 1 }
            return self.nextStepIndex
        }
        guard let index = claimed else { return }
        let files: (step: URL, zoom: URL?)
        do {
            files = try Self.writeFiles(step, index: index, in: folder)
        } catch {
            NSLog("Clipr: advanced mode step save failed: \(error)")
            return
        }
        let record = StepRecord(
            id: UUID(), file: files.step.lastPathComponent, kind: step.kind, caption: step.caption,
            clickPoint: step.clickPoint, zoomFile: files.zoom?.lastPathComponent, appName: step.appName,
            capturedAt: step.capturedAt
        )
        let snapshot: SessionManifest? = await MainActor.run {
            guard self.manifest != nil, folder == self.sessionFolder else { return nil }
            self.manifest?.steps.append(record)
            return self.manifest
        }
        guard let snapshot else {
            // The session ended while the files were being written; they belong to no manifest.
            for url in [files.step, files.zoom].compactMap({ $0 }) + [Self.annotationsURL(for: files.step)] {
                try? FileManager.default.removeItem(at: url)
            }
            return
        }
        do {
            try SessionManifestStore.save(snapshot, in: folder)
            SessionFolder.restrict(folder.appendingPathComponent(SessionManifestStore.fileName))
        } catch {
            NSLog("Clipr: advanced mode manifest save failed: \(error)")
        }
        await MainActor.run { self.onStepCaptured?(snapshot.steps.count) }
    }

    private func isFrontmostClipr() -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }
}
