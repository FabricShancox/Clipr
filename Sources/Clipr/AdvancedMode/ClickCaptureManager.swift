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
    /// The focused field at the current burst's first accepted printable key.
    private var burstStartField: Task<FocusedField, Never>?
    /// The focused field at the burst's latest accepted printable key. Each read is chained after
    /// the previous one so the answers arrive in key order.
    private var burstLastField: Task<FocusedField, Never>?
    /// Clipr's own hotkeys. The listen-only tap sees their keyDown before Carbon dispatches them,
    /// so without this every press would also become a "Press ⌘⇧2" typing step.
    private var ignoredKeys: [HotkeyBinding] = []
    private var idleWork: DispatchWorkItem?
    private var pending: PendingClick?
    /// The tail of the write chain. Captures run concurrently, but every step awaits the one
    /// before it before writing, so steps land in the order the user did them even when a slow
    /// capture finishes after a fast one. `stop` awaits this to know everything is on disk.
    private var lastWrite: Task<Void, Never>?
    private var isStopping = false

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
            discardTypingBurst()
            if let pending {
                pending.work.cancel()
                self.pending = nil
                fire(pending)
            }
        }
    }
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
        trail = CursorTrailRecorder()
        keystrokes = KeystrokeAggregator()
        burstStartField = nil
        burstLastField = nil
        self.ignoredKeys = ignoredKeys
        lastWrite = nil
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
        endTypingBurst()
        idleWork?.cancel()
        let last = lastWrite
        Task { @MainActor in
            // Capped so a hung ScreenCaptureKit call can't leave Stop dead forever. On timeout
            // the session completes with what's written so far; `write` drops any late step
            // because the manifest and session folder are cleared below.
            if let last, await Self.value(of: last, timeout: Self.stopFlushTimeout) == nil {
                NSLog("Clipr: advanced mode stop gave up waiting for in-flight steps")
            }
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
        case .click(let p, let clickCount):
            endTypingBurst()
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
            let slot = reserveWriteSlot()
            let describe = settings.autoCaptions ? Task { await self.describer.describe(at: p) } : nil
            let work = DispatchWorkItem { [weak self] in
                guard let self, let pending = self.pending else { return }
                self.pending = nil
                self.fire(pending)
            }
            pending = PendingClick(point: p, trail: points, describe: describe, work: work, slot: slot)
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.effectiveDelay, execute: work)
        case .key(let key):
            guard settings.typingSteps, !typingUnavailable, !isFrontmostClipr(),
                  !ignoredKeys.contains(where: { $0.matches(key) }) else { return }
            let before = keystrokes.bufferedCharacterCount
            for typed in keystrokes.handle(key, at: Date()) { emit(typed) }
            // Only a key the burst actually took as text reads the focused field — not arrows,
            // Escape, shortcuts or the Return/Tab that ends a burst.
            if keystrokes.bufferedCharacterCount > before { readFocusedField(startsBurst: before == 0) }
            scheduleIdleCheck()
        }
    }

    /// Points a double-click's second press may drift from the first and still be the same click.
    static let doubleClickSlop: CGFloat = 6

    /// The second press of a double-click (or triple-click) on the same spot, as opposed to a
    /// quick click on another control.
    static func isRepeatClick(clickCount: Int, at point: CGPoint, after previous: CGPoint) -> Bool {
        clickCount > 1 && hypot(point.x - previous.x, point.y - previous.y) <= doubleClickSlop
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

    private func discardTypingBurst() {
        idleWork?.cancel()
        idleWork = nil
        keystrokes = KeystrokeAggregator()
        burstStartField = nil
        burstLastField = nil
    }

    /// Read at the key, not at the end of the burst: by the time a Tab or click ends the burst
    /// it has already reached the app, so a read then would usually see the next field and the
    /// step would be dropped as a focus change.
    private func readFocusedField(startsBurst: Bool) {
        let previous = burstLastField
        let read = Task { _ = await previous?.value; return await self.describer.focusedField() }
        if startsBurst { burstStartField = read }
        burstLastField = read
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
        switch typed {
        case .shortcut(let keys):
            enqueue(kind: .typing, target: scopeTarget(for: nil), click: nil, trail: [], caption: { _ in CaptionFormatter.shortcut(keys) })
        case .text(let text):
            let start = burstStartField, last = burstLastField
            burstStartField = nil
            burstLastField = nil
            // The aggregator never emits an empty burst; checked here too because an empty
            // typing step would be a screenshot captioned `Type ""`.
            guard !text.isEmpty else { return }
            // The focused-field check is the second line of defence after `IsSecureEventInputEnabled`
            // (some password fields don't turn secure input on). It fails closed: the field read
            // at the burst's first key and at its last key must be the same element, known not
            // secure both times, or the step is dropped before anything is captured. Focus can
            // move mid-burst without a click or Tab, so one read could vouch for one field while
            // the text went into a password field.
            enqueue(kind: .typing, target: scopeTarget(for: nil), click: nil, trail: [], skipIf: {
                guard let start, let last else { return true }
                return !Self.isSameNonSecureField(await start.value, await last.value)
            }, caption: { _ in
                CaptionFormatter.typing(text, fieldLabel: await start?.value.label)
            })
        }
    }

    /// Both reads known not secure, and of the same element. Fakes have no element, so two `nil`s
    /// count as the same field — but only when both reads are `notSecure` anyway.
    private static func isSameNonSecureField(_ a: FocusedField, _ b: FocusedField) -> Bool {
        guard a.security == .notSecure, b.security == .notSecure else { return false }
        switch (a.element, b.element) {
        case (nil, nil): return true
        case let (x?, y?): return CFEqual(x, y)
        default: return false
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
        // Waits for its predecessor too, so finishing a superseded click's slot early can't
        // let later steps (or `stop`) skip past a step that's still capturing.
        lastWrite = Task {
            for await _ in stream {}
            await predecessor?.value
        }
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
                target: target, imageSource: imageSource, showsCursor: showsCursor, skipIf: skipIf,
                kind: kind, click: click, trail: trail, settings: settings, caption: caption
            )
            await predecessor?.value
            guard let self, let prepared else { return }
            await self.write(prepared, folder: folder)
        }
        if slot == nil { lastWrite = task }
    }

    /// One step's files, encoded and ready to write.
    struct PreparedStep {
        let png: Data
        let annotations: [AnnotationObject]
        let zoomPNG: Data?
        let kind: StepRecord.Kind
        let caption: String?
        let clickPoint: CGPoint?
        let appName: String?
        let capturedAt: Date
    }

    /// Captures, captions and encodes a step. The captured bitmap lives only inside this call.
    private static func captureAndPrepare(
        target: CaptureTarget, imageSource: StepImageSource, showsCursor: Bool, skipIf: () async -> Bool,
        kind: StepRecord.Kind, click: CGPoint?, trail: [CGPoint], settings: AdvancedModeSettings,
        caption: (_ appName: String?) async -> String?
    ) async -> PreparedStep? {
        guard await !skipIf() else { return nil }
        let frame: CapturedFrame?
        do {
            frame = try await imageSource.capture(target, showsCursor: showsCursor)
        } catch {
            NSLog("Clipr: advanced mode step capture failed: \(error)")
            return nil
        }
        guard let frame else { return nil }
        let text = await caption(frame.appName)
        return autoreleasepool {
            prepare(frame, kind: kind, click: click, trail: trail, caption: text, settings: settings)
        }
    }

    /// Pure: the encoded step image, its marker/trail annotations and zoom crop. Nil only if the
    /// image won't encode.
    static func prepare(_ frame: CapturedFrame, kind: StepRecord.Kind, click: CGPoint?, trail: [CGPoint],
                        caption: String?, settings: AdvancedModeSettings, capturedAt: Date = Date()) -> PreparedStep? {
        guard let png = StepFiles.pngData(frame.image) else {
            NSLog("Clipr: advanced mode step encode failed")
            return nil
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
        var zoomPNG: Data?
        if settings.zoomOnClick, let imagePoint, let zoom = StepZoom.image(from: frame.image, centeredOn: imagePoint) {
            zoomPNG = StepFiles.pngData(zoom)
        }
        return PreparedStep(png: png, annotations: annotations, zoomPNG: zoomPNG, kind: kind, caption: caption,
                            clickPoint: imagePoint, appName: frame.appName, capturedAt: capturedAt)
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

    /// PNG → annotations sidecar → zoom, each owner-only, so the manifest never names a file that
    /// isn't on disk. A sidecar or zoom that fails to write is logged and left out.
    static func writeFiles(_ step: PreparedStep, index: Int, in folder: URL) throws -> (step: URL, zoom: URL?) {
        let stepURL = availableStepURL(index: index, in: folder)
        try step.png.write(to: stepURL, options: .atomic)
        SessionFolder.restrict(stepURL)
        if !step.annotations.isEmpty {
            let sidecar = annotationsURL(for: stepURL)
            do {
                try JSONEncoder().encode(step.annotations).write(to: sidecar, options: .atomic)
                SessionFolder.restrict(sidecar)
            } catch {
                NSLog("Clipr: advanced mode marker save failed: \(error)")
            }
        }
        var zoomURL: URL?
        if let zoomPNG = step.zoomPNG {
            let url = folder.appendingPathComponent(FilenameGenerator.zoomName(fromStep: stepURL.lastPathComponent))
            do {
                try zoomPNG.write(to: url, options: .atomic)
                SessionFolder.restrict(url)
                zoomURL = url
            } catch {
                NSLog("Clipr: advanced mode zoom save failed: \(error)")
            }
        }
        return (stepURL, zoomURL)
    }

    /// `Step_NN.png`, or `Step_NN_1.png` … if something else already put a file there.
    private static func availableStepURL(index: Int, in folder: URL) -> URL {
        let url = folder.appendingPathComponent(FilenameGenerator.stepName(index: index))
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        var suffix = 1
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(base)_\(suffix).png").path) { suffix += 1 }
        return folder.appendingPathComponent("\(base)_\(suffix).png")
    }

    private static func annotationsURL(for stepURL: URL) -> URL {
        stepURL.deletingLastPathComponent().appendingPathComponent(FilenameGenerator.annotationsName(fromRaw: stepURL.lastPathComponent))
    }

    private func isFrontmostClipr() -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    /// `task`'s value, or `nil` if it takes longer than `timeout` — a slow AX read falls back to
    /// the generic caption instead of holding the step back, and a hung capture can't hold up
    /// `stop` forever. A race of two unstructured tasks
    /// rather than a task group: a group waits for every child before returning, and awaiting
    /// `task.value` ignores cancellation, so a group would never actually cut a slow read short.
    private static func value<T>(of task: Task<T, Never>?, timeout: TimeInterval) async -> T? {
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

extension HotkeyBinding {
    /// Same key and exactly the same ⌃⌥⇧⌘ modifiers. Carbon modifier bits mapped to `KeyModifiers`.
    func matches(_ key: KeyInput) -> Bool {
        guard UInt32(key.keyCode) == keyCode else { return false }
        var expected: KeyModifiers = []
        if modifiers & Modifier.command.rawValue != 0 { expected.insert(.command) }
        if modifiers & Modifier.shift.rawValue != 0 { expected.insert(.shift) }
        if modifiers & Modifier.option.rawValue != 0 { expected.insert(.option) }
        if modifiers & Modifier.control.rawValue != 0 { expected.insert(.control) }
        return key.modifiers == expected
    }
}
