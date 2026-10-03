// Sources/Clipr/AdvancedMode/ClickCaptureManager.swift
import Cocoa

/// Runs one Advanced Mode session: turns tap events into steps according to the settings
/// snapshot taken at `start`, and writes each step as PNG → annotations sidecar → zoom →
/// `session.json`, in that order, so the manifest never names a file that isn't on disk.
final class ClickCaptureManager {
    private let storage: StorageManager
    private let imageSource: StepImageSource
    private let describer: ClickDescribing
    private let eventSource: SessionEventSource
    private let accessibilityGranted: () -> Bool
    private let inputMonitoringGranted: () -> Bool

    private var sessionFolder: URL?
    private var manifest: SessionManifest?
    private var settings = AdvancedModeSettings.default
    private var area: CGRect?
    private var nextStepIndex = 1
    private var trail = CursorTrailRecorder()
    private var keystrokes = KeystrokeAggregator()
    private var typingFieldTask: Task<(label: String?, isSecure: Bool), Never>?
    private var idleWork: DispatchWorkItem?
    private var pending: PendingClick?
    /// The tail of the write chain. Captures run concurrently, but every step awaits the one
    /// before it before writing, so steps land in the order the user did them even when a slow
    /// capture finishes after a fast one. `stop` awaits this to know everything is on disk.
    private var lastWrite: Task<Void, Never>?
    private var isStopping = false

    var isPaused = false
    var captureCursor = false
    private(set) var typingUnavailable = false
    var onStepCaptured: ((Int) -> Void)?

    var isActive: Bool { sessionFolder != nil }
    var currentSessionFolder: URL? { sessionFolder }
    var ownWindowIDs: Set<CGWindowID> {
        get { imageSource.ownWindowIDs }
        set { imageSource.ownWindowIDs = newValue }
    }

    private struct PendingClick {
        let point: CGPoint
        let trail: [CGPoint]
        let describe: Task<ClickTarget?, Never>?
        let work: DispatchWorkItem
        let slot: WriteSlot
    }

    /// A place in the write chain reserved when the user clicked, not when the delayed capture
    /// fires — otherwise a typing burst that ends inside the click's delay (e.g. on Stop) would
    /// be written before the click that came first.
    private struct WriteSlot {
        let predecessor: Task<Void, Never>?
        let done: AsyncStream<Void>.Continuation
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
        eventSource.onEvent = { [weak self] in self?.handle($0) }
    }

    // MARK: Lifecycle

    func start(settings: AdvancedModeSettings, area: CGRect?) throws -> URL {
        guard accessibilityGranted() else {
            PermissionsManager.requestAccessibilityPermission()
            throw ClickCaptureError.accessibilityNotGranted
        }
        let now = Date()
        let folder = try storage.createSessionFolder(date: now)
        self.settings = settings
        self.area = area
        typingUnavailable = settings.typingSteps && !inputMonitoringGranted()
        manifest = SessionManifest(createdAt: now)
        nextStepIndex = 1
        trail = CursorTrailRecorder()
        keystrokes = KeystrokeAggregator()
        lastWrite = nil
        isPaused = false
        // Before `sessionFolder` is set, so a failure can't leave `isActive` true with no tap.
        try eventSource.start(options: SessionEventOptions(
            mouseMoves: settings.cursorTrail,
            keys: settings.typingSteps && !typingUnavailable
        ))
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
        endTypingBurst()
        idleWork?.cancel()
        let last = lastWrite
        Task { @MainActor in
            await last?.value
            let final = self.manifest
            self.sessionFolder = nil
            self.manifest = nil
            self.lastWrite = nil
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
            endTypingBurst()
        case .click(let p):
            endTypingBurst()
            var points = trail.drain()
            let slot: WriteSlot
            if let previous = pending {
                // A second click inside the delay replaces the first (double-click, fast
                // clicking); its trail is kept so the path still starts where the user began,
                // and so is its place in the write order.
                previous.work.cancel()
                previous.describe?.cancel()
                points = previous.trail + points
                slot = previous.slot
            } else {
                slot = reserveWriteSlot()
            }
            let describe = settings.autoCaptions ? Task { await self.describer.describe(at: p) } : nil
            let work = DispatchWorkItem { [weak self] in
                guard let self, let pending = self.pending else { return }
                self.pending = nil
                self.fire(pending)
            }
            pending = PendingClick(point: p, trail: points, describe: describe, work: work, slot: slot)
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.effectiveDelay, execute: work)
        case .key(let key):
            guard settings.typingSteps, !typingUnavailable, !isFrontmostClipr() else { return }
            if !keystrokes.hasPendingBurst { typingFieldTask = Task { await self.describer.focusedField() } }
            for typed in keystrokes.handle(key, at: Date()) { emit(typed) }
            scheduleIdleCheck()
        }
    }

    // MARK: Steps

    private func fire(_ click: PendingClick) {
        let caption: (String?) async -> String? = { [autoCaptions = settings.autoCaptions, describe = click.describe] appName in
            guard autoCaptions else { return nil }
            let target = await Self.value(of: describe, timeout: 0.5)
            return CaptionFormatter.click(target ?? nil, appName: appName)
        }
        enqueue(kind: .click, target: scopeTarget(for: click.point), click: click.point, trail: click.trail,
                slot: click.slot, caption: caption)
    }

    private func endTypingBurst() {
        idleWork?.cancel()
        if let typed = keystrokes.endBurst() { emit(typed) }
    }

    private func scheduleIdleCheck() {
        idleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let typed = self.keystrokes.idleCheck(now: Date()) else { return }
            self.emit(typed)
        }
        idleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + KeystrokeAggregator.idleTimeout, execute: work)
    }

    private func emit(_ typed: TypingEvent) {
        let field = typingFieldTask
        typingFieldTask = nil
        switch typed {
        case .shortcut(let keys):
            enqueue(kind: .typing, target: scopeTarget(for: nil), click: nil, trail: [], caption: { _ in CaptionFormatter.shortcut(keys) })
        case .text(let text):
            // The aggregator never emits an empty burst; checked here too because an empty
            // typing step would be a screenshot captioned `Type ""`.
            guard !text.isEmpty else { return }
            // The focused-field check is the second line of defence after `IsSecureEventInputEnabled`
            // (some password fields don't turn secure input on): a secure field drops the step.
            enqueue(kind: .typing, target: scopeTarget(for: nil), click: nil, trail: [], skipIf: {
                await field?.value.isSecure ?? false
            }, caption: { _ in
                CaptionFormatter.typing(text, fieldLabel: await field?.value.label)
            })
        }
    }

    private func scopeTarget(for click: CGPoint?) -> CaptureTarget {
        switch settings.scope {
        case .window:
            return .frontmostWindow
        case .screen:
            return .screenContaining(click ?? NSEvent.mouseLocationQuartz)
        case .fixedArea:
            return area.map { .area($0) } ?? .frontmostWindow
        }
    }

    /// Appends a placeholder to the write chain that completes when `done` is finished.
    private func reserveWriteSlot() -> WriteSlot {
        let (stream, done) = AsyncStream<Void>.makeStream()
        let predecessor = lastWrite
        lastWrite = Task { for await _ in stream {} }
        return WriteSlot(predecessor: predecessor, done: done)
    }

    /// `slot` is the click's reserved place in the chain; every other step joins at the end now.
    private func enqueue(
        kind: StepRecord.Kind, target: CaptureTarget, click: CGPoint?, trail: [CGPoint],
        slot: WriteSlot? = nil,
        skipIf: @escaping () async -> Bool = { false }, caption: @escaping (_ appName: String?) async -> String?
    ) {
        guard let folder = sessionFolder else {
            slot?.done.finish()
            return
        }
        let predecessor = slot.map(\.predecessor) ?? lastWrite
        let settings = self.settings
        let showsCursor = captureCursor
        let imageSource = self.imageSource
        let task = Task { [weak self] in
            // Released however this step ends — written, skipped or failed — so the steps
            // queued behind it are never stuck waiting.
            defer { slot?.done.finish() }
            var frame: CapturedFrame?
            if await !skipIf() {
                do {
                    frame = try await imageSource.capture(target, showsCursor: showsCursor)
                } catch {
                    NSLog("Clipr: advanced mode step capture failed: \(error)")
                }
            }
            let text = if let frame { await caption(frame.appName) } else { String?.none }
            await predecessor?.value
            guard let self, let frame else { return }
            await MainActor.run {
                self.write(frame, kind: kind, click: click, trail: trail, caption: text, settings: settings, folder: folder)
            }
        }
        if slot == nil { lastWrite = task }
    }

    /// Main actor only, so the index increment and manifest append can never interleave.
    private func write(_ frame: CapturedFrame, kind: StepRecord.Kind, click: CGPoint?, trail: [CGPoint],
                       caption: String?, settings: AdvancedModeSettings, folder: URL) {
        guard manifest != nil else { return }
        let index = nextStepIndex
        nextStepIndex += 1
        let stepURL: URL
        do {
            stepURL = try storage.saveStep(frame.image, index: index, in: folder)
        } catch {
            NSLog("Clipr: advanced mode step save failed: \(error)")
            return
        }
        let size = frame.image.size
        let imagePoint = click.flatMap { StepGeometry.imagePoint(global: $0, captureOrigin: frame.origin, imageSize: size) }

        var annotations: [AnnotationObject] = []
        if settings.cursorTrail, kind == .click, let click,
           let path = StepAnnotationFactory.trail(globalPoints: trail + [click], captureOrigin: frame.origin, imageSize: size) {
            annotations.append(path)
        }
        if settings.clickMarker, let imagePoint {
            annotations.append(StepAnnotationFactory.marker(at: imagePoint, style: settings.markerStyle, imageSize: size))
        }
        if !annotations.isEmpty {
            do { try storage.saveAnnotations(annotations, rawURL: stepURL) } catch {
                NSLog("Clipr: advanced mode marker save failed: \(error)")
            }
        }

        var zoomFile: String?
        if settings.zoomOnClick, let imagePoint, let zoom = StepZoom.image(from: frame.image, centeredOn: imagePoint) {
            do { zoomFile = try storage.saveStepZoom(zoom, stepURL: stepURL).lastPathComponent } catch {
                NSLog("Clipr: advanced mode zoom save failed: \(error)")
            }
        }

        manifest?.steps.append(StepRecord(
            id: UUID(), file: stepURL.lastPathComponent, kind: kind, caption: caption,
            clickPoint: imagePoint, zoomFile: zoomFile, appName: frame.appName, capturedAt: Date()
        ))
        if let manifest {
            do { try SessionManifestStore.save(manifest, in: folder) } catch {
                NSLog("Clipr: advanced mode manifest save failed: \(error)")
            }
            onStepCaptured?(manifest.steps.count)
        }
    }

    private func isFrontmostClipr() -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    /// `task`'s value, or `nil` if it takes longer than `timeout` — a slow AX read falls back to
    /// the generic caption instead of holding the step back. A race of two unstructured tasks
    /// rather than a task group: a group waits for every child before returning, and awaiting
    /// `task.value` ignores cancellation, so a group would never actually cut a slow read short.
    private static func value<T>(of task: Task<T?, Never>?, timeout: TimeInterval) async -> T?? {
        guard let task else { return nil }
        return await withCheckedContinuation { continuation in
            let first = FirstResult()
            Task {
                let value = await task.value
                if first.claim() { continuation.resume(returning: .some(value)) }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if first.claim() { continuation.resume(returning: nil) }
            }
        }
    }
}

/// Lets exactly one of two racing tasks resume a continuation.
private final class FirstResult: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

private extension NSEvent {
    /// `NSEvent.mouseLocation` is AppKit space; steps work in Quartz global space.
    static var mouseLocationQuartz: CGPoint {
        let p = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}
