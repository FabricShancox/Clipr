// Tests/ClipprTests/ClickCaptureManagerTests.swift
import XCTest
@testable import Clipr

private final class FakeSource: SessionEventSource {
    var onEvent: ((SessionEvent) -> Void)?
    var startedWith: SessionEventOptions?
    var startError: Error?
    func start(options: SessionEventOptions) throws {
        if let startError { throw startError }
        startedWith = options
    }
    func stop() {}
}

private final class FakeImages: StepImageSource {
    var ownWindowIDs: Set<CGWindowID> = []
    var targets: [CaptureTarget] = []
    let origin = CGPoint(x: 100, y: 100)
    /// How long a capture of `target` takes, so a test can hold one step in flight.
    var delay: (CaptureTarget) -> TimeInterval = { _ in 0 }
    func capture(_ target: CaptureTarget, showsCursor: Bool) async throws -> CapturedFrame? {
        let seconds = delay(target)
        if seconds > 0 { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
        await MainActor.run { self.targets.append(target) }
        let image = testImage(width: 400, height: 300) { NSColor.white.set(); NSRect(x: 0, y: 0, width: 400, height: 300).fill() }
        return CapturedFrame(image: image, origin: origin, appName: "Safari", marksClick: marksClick)
    }
    var marksClick = true
}

private final class FakeDescriber: ClickDescribing {
    var target: ClickTarget? = ClickTarget(role: "AXButton", subrole: nil, label: "Save", menuPath: [])
    var field = FocusedField(label: "Name", security: .notSecure, element: nil)
    /// Answers for successive `focusedField()` calls; the last one keeps being answered once
    /// it's reached, so `[start, end]` means "the first key saw `start`, every later key `end`".
    /// The manager chains a burst's reads, so this order is deterministic. `field` when empty.
    var fields: [FocusedField] = []
    /// Once set, every read answers this — a stand-in for the next field that a Tab or click
    /// moved focus to before any read issued after it could run.
    var afterBoundary: FocusedField?
    /// Called with the running read count after each `focusedField()` call.
    var onRead: ((Int) -> Void)?
    private(set) var readCount = 0
    private let lock = NSLock()
    func describe(at point: CGPoint) async -> ClickTarget? { target }
    func focusedField() async -> FocusedField { nextField() }

    func passBoundary(to field: FocusedField) {
        lock.lock(); defer { lock.unlock() }
        afterBoundary = field
    }

    private func nextField() -> FocusedField {
        lock.lock()
        readCount += 1
        let count = readCount
        let answer: FocusedField
        if let afterBoundary {
            answer = afterBoundary
        } else if fields.count > 1 {
            answer = fields.removeFirst()
        } else {
            answer = fields.first ?? field
        }
        let onRead = self.onRead
        lock.unlock()
        onRead?(count)
        return answer
    }
}

final class ClickCaptureManagerTests: XCTestCase {
    var folder: URL!
    fileprivate var source: FakeSource!
    fileprivate var images: FakeImages!
    fileprivate var describer: FakeDescriber!
    var manager: ClickCaptureManager!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        source = FakeSource(); images = FakeImages(); describer = FakeDescriber()
        manager = ClickCaptureManager(
            storage: StorageManager(baseFolder: folder), imageSource: images, describer: describer,
            eventSource: source, accessibilityGranted: { true }, inputMonitoringGranted: { true }
        )
        // Two side-by-side displays, independent of the machine running the tests.
        manager.screenFrames = { [CGRect(x: 0, y: 0, width: 1920, height: 1080), CGRect(x: 1920, y: 0, width: 1920, height: 1080)] }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func settings(_ edit: (inout AdvancedModeSettings) -> Void = { _ in }) -> AdvancedModeSettings {
        var s = AdvancedModeSettings.default
        s.captureDelay = 0.2
        edit(&s)
        return s
    }

    private func stop() -> (SessionManifest, URL) {
        let done = expectation(description: "stopped")
        var result: (SessionManifest, URL)!
        manager.stop { manifest, folder in result = (manifest!, folder!); done.fulfill() }
        wait(for: [done], timeout: 5)
        return result
    }

    private func waitForSteps(_ n: Int) {
        let reached = expectation(description: "\(n) steps")
        manager.onStepCaptured = { if $0 == n { reached.fulfill() } }
        wait(for: [reached], timeout: 5)
    }

    func testTapOptionsFollowSettings() throws {
        _ = try manager.start(settings: settings { $0.cursorTrail = true; $0.typingSteps = true }, area: nil)
        XCTAssertEqual(source.startedWith, SessionEventOptions(mouseMoves: true, keys: true))
    }

    // L2: a tap that fails to start leaves no empty session folder behind.
    func testFailedTapStartRemovesSessionFolder() throws {
        source.startError = ClickCaptureError.eventTapCreationFailed
        XCTAssertThrowsError(try manager.start(settings: settings(), area: nil))
        XCTAssertFalse(manager.isActive)
        let entries = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertFalse(entries.contains { $0.hasPrefix("Session_") }, "left behind: \(entries)")
    }

    func testTypingDisabledWithoutInputMonitoring() throws {
        manager = ClickCaptureManager(storage: StorageManager(baseFolder: folder), imageSource: images, describer: describer,
                                      eventSource: source, accessibilityGranted: { true }, inputMonitoringGranted: { false })
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        XCTAssertEqual(source.startedWith?.keys, false)
        XCTAssertTrue(manager.typingUnavailable)
    }

    private func waitForProblem(_ problem: StepSaveProblem) {
        let reported = expectation(description: "\(problem)")
        manager.onSaveProblem = { if $0 == problem { reported.fulfill() } }
        wait(for: [reported], timeout: 5)
    }

    // A step whose PNG can't be written is skipped and reported, and doesn't use up its number.
    func testFailedStepWriteIsReportedAndLeavesNoNumberingGap() throws {
        let sessionFolder = try manager.start(settings: settings(), area: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: sessionFolder.path)
        manager.captureManualStep()
        waitForProblem(.stepDropped)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sessionFolder.path)
        manager.captureManualStep()
        waitForSteps(1)
        let (manifest, _) = stop()
        XCTAssertEqual(manifest.steps.map(\.file), [FilenameGenerator.stepName(index: 1)])
    }

    // A session.json that can't be saved isn't reported as a captured step.
    func testFailedManifestSaveIsReportedNotCounted() throws {
        let sessionFolder = try manager.start(settings: settings(), area: nil)
        try FileManager.default.createDirectory(
            at: sessionFolder.appendingPathComponent(SessionManifestStore.fileName), withIntermediateDirectories: true)
        let counted = expectation(description: "counted")
        counted.isInverted = true
        let reported = expectation(description: "reported")
        manager.onStepCaptured = { _ in counted.fulfill() }
        manager.onSaveProblem = { if $0 == .manifestNotSaved { reported.fulfill() } }
        manager.captureManualStep()
        wait(for: [reported, counted], timeout: 2)
        _ = stop()
    }

    func testClickWritesPNGAnnotationsAndManifestWithCaption() throws {
        _ = try manager.start(settings: settings(), area: nil)
        manager.handle(.click(CGPoint(x: 150, y: 160)))
        waitForSteps(1)
        let (manifest, sessionFolder) = stop()
        XCTAssertEqual(manifest.steps.count, 1)
        let step = manifest.steps[0]
        XCTAssertEqual(step.kind, .click)
        XCTAssertEqual(step.caption, "Click **Save** in Safari")
        XCTAssertEqual(step.clickPoint, CGPoint(x: 50, y: 60))
        XCTAssertEqual(step.appName, "Safari")
        let rawURL = sessionFolder.appendingPathComponent(step.file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rawURL.path))
        let annotations = StorageManager(baseFolder: folder).loadAnnotations(rawURL: rawURL)
        XCTAssertEqual(annotations.count, 1)
        XCTAssertEqual(annotations[0].kind, .ellipse)
        // Compared by fields, not whole value: ISO-8601 on disk drops sub-second `capturedAt`.
        let onDisk = SessionManifestStore.load(from: sessionFolder)
        XCTAssertEqual(onDisk.steps.map(\.file), manifest.steps.map(\.file))
        XCTAssertEqual(onDisk.steps.map(\.caption), manifest.steps.map(\.caption))
        XCTAssertEqual(images.targets, [.frontmostWindow])
    }

    func testRapidClicksCoalesceIntoOneStepKeepingTrail() throws {
        _ = try manager.start(settings: settings { $0.cursorTrail = true }, area: nil)
        manager.handle(.mouseMoved(CGPoint(x: 110, y: 110)))
        manager.handle(.mouseMoved(CGPoint(x: 130, y: 110)))
        manager.handle(.click(CGPoint(x: 140, y: 120)))
        manager.handle(.mouseMoved(CGPoint(x: 142, y: 121)))
        manager.handle(.click(CGPoint(x: 142, y: 122), clickCount: 2))   // the double-click's second press
        waitForSteps(1)
        let (manifest, sessionFolder) = stop()
        XCTAssertEqual(manifest.steps.count, 1)
        XCTAssertEqual(manifest.steps[0].clickPoint, CGPoint(x: 42, y: 22))
        let annotations = StorageManager(baseFolder: folder).loadAnnotations(rawURL: sessionFolder.appendingPathComponent(manifest.steps[0].file))
        let trail = annotations.first { if case .freehand = $0.kind { return true }; return false }
        guard case .freehand(let pts)? = trail?.kind else { return XCTFail("no trail") }
        // Starts at the first move (kept across the coalesced click) and ends on the final click.
        XCTAssertEqual(pts.first, CGPoint(x: 10, y: 290))
        XCTAssertEqual(pts.last, CGPoint(x: 42, y: 278))
    }

    // M1: a second click on a different control inside the delay is a step of its own.
    func testSecondClickElsewhereInsideDelayKeepsBothSteps() throws {
        _ = try manager.start(settings: settings { $0.captureDelay = 1.5 }, area: nil)
        manager.handle(.click(CGPoint(x: 150, y: 160)))   // ticks a checkbox
        manager.handle(.click(CGPoint(x: 300, y: 250)))   // then OK, well inside the delay
        let steps = stop().0.steps
        XCTAssertEqual(steps.map(\.clickPoint), [CGPoint(x: 50, y: 60), CGPoint(x: 200, y: 150)])
    }

    // M1: a repeat press far from the first isn't the same double-click either.
    // A slow double-click: the first press was already captured when the second arrives (still
    // within the double-click interval, on the same spot), so it replaces that step.
    func testSlowDoubleClickReplacesTheAlreadyCapturedStep() throws {
        var clock: TimeInterval = 100
        manager.now = { clock }
        manager.doubleClickInterval = { 0.5 }
        _ = try manager.start(settings: settings { $0.zoomOnClick = true }, area: nil)
        manager.handle(.click(CGPoint(x: 140, y: 120)))
        waitForSteps(1)
        clock += 0.4
        manager.handle(.click(CGPoint(x: 143, y: 122), clickCount: 2))
        waitForSteps(1)
        let (manifest, sessionFolder) = stop()
        XCTAssertEqual(manifest.steps.map(\.file), [FilenameGenerator.stepName(index: 1)])
        XCTAssertEqual(manifest.steps[0].clickPoint, CGPoint(x: 43, y: 22), "the second press")
        XCTAssertEqual(SessionManifestStore.load(from: sessionFolder).steps.map(\.id), manifest.steps.map(\.id))
        XCTAssertEqual(SessionManifestStore.rawStepFiles(in: sessionFolder), [FilenameGenerator.stepName(index: 1)])
    }

    func testSecondPressAfterTheDoubleClickIntervalIsANewStep() throws {
        var clock: TimeInterval = 100
        manager.now = { clock }
        manager.doubleClickInterval = { 0.5 }
        _ = try manager.start(settings: settings(), area: nil)
        manager.handle(.click(CGPoint(x: 140, y: 120)))
        waitForSteps(1)
        clock += 0.6
        manager.handle(.click(CGPoint(x: 140, y: 120), clickCount: 2))
        waitForSteps(2)
        XCTAssertEqual(stop().0.steps.count, 2)
    }

    func testRepeatClickCountFarAwayIsNotADoubleClick() throws {
        _ = try manager.start(settings: settings { $0.captureDelay = 1.5 }, area: nil)
        manager.handle(.click(CGPoint(x: 150, y: 160)))
        manager.handle(.click(CGPoint(x: 300, y: 250), clickCount: 2))
        XCTAssertEqual(stop().0.steps.count, 2)
    }

    func testClickOutsideImageHasNoMarkerOrZoom() throws {
        _ = try manager.start(settings: settings { $0.zoomOnClick = true }, area: nil)
        manager.handle(.click(CGPoint(x: 5, y: 5)))   // left of origin (100,100)
        waitForSteps(1)
        let (manifest, sessionFolder) = stop()
        XCTAssertNil(manifest.steps[0].clickPoint)
        XCTAssertNil(manifest.steps[0].zoomFile)
        XCTAssertTrue(StorageManager(baseFolder: folder).loadAnnotations(rawURL: sessionFolder.appendingPathComponent(manifest.steps[0].file)).isEmpty)
    }

    // Security #6: step files are owner-only.
    func testStepFilesAreOwnerOnly() throws {
        _ = try manager.start(settings: settings { $0.zoomOnClick = true }, area: nil)
        manager.handle(.click(CGPoint(x: 300, y: 250)))
        waitForSteps(1)
        let (_, sessionFolder) = stop()
        for name in ["Step_01.png", "Step_01_zoom.png", FilenameGenerator.annotationsName(fromRaw: "Step_01.png"), "session.json"] {
            let attributes = try FileManager.default.attributesOfItem(atPath: sessionFolder.appendingPathComponent(name).path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600, name)
        }
    }

    func testPrepareEncodesMarkerAndZoomWithoutTouchingDisk() throws {
        let image = testImage(width: 400, height: 300) { NSColor.white.set(); NSRect(x: 0, y: 0, width: 400, height: 300).fill() }
        let frame = CapturedFrame(image: image, origin: CGPoint(x: 100, y: 100), appName: "Safari")
        let prepared = try XCTUnwrap(ClickCaptureManager.prepare(
            frame, kind: .click, click: CGPoint(x: 300, y: 250), trail: [], caption: "c",
            settings: settings { $0.zoomOnClick = true }
        ))
        XCTAssertEqual(prepared.clickPoint, CGPoint(x: 200, y: 150))
        XCTAssertEqual(prepared.annotations.count, 1)
        XCTAssertNotNil(prepared.zoomPNG)
        XCTAssertNotNil(NSImage(data: prepared.png))
    }

    func testZoomWrittenAndRecorded() throws {
        _ = try manager.start(settings: settings { $0.zoomOnClick = true }, area: nil)
        manager.handle(.click(CGPoint(x: 300, y: 250)))
        waitForSteps(1)
        let (manifest, sessionFolder) = stop()
        XCTAssertEqual(manifest.steps[0].zoomFile, "Step_01_zoom.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionFolder.appendingPathComponent("Step_01_zoom.png").path))
    }

    func testCaptionsOffMeansNoCaption() throws {
        _ = try manager.start(settings: settings { $0.autoCaptions = false }, area: nil)
        manager.handle(.click(CGPoint(x: 150, y: 160)))
        waitForSteps(1)
        XCTAssertNil(stop().0.steps[0].caption)
    }

    func testTypingBurstEndedByClickBecomesItsOwnStepFirst() throws {
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        for ch in "John" {
            manager.handle(.key(KeyInput(characters: String(ch), baseCharacters: String(ch), keyCode: 0, modifiers: [], isSecure: false)))
        }
        manager.handle(.click(CGPoint(x: 150, y: 160)))
        waitForSteps(2)
        let steps = stop().0.steps
        XCTAssertEqual(steps.map(\.kind), [.typing, .click])
        XCTAssertEqual(steps[0].caption, #"Type "John" in **Name**"#)
        XCTAssertNil(steps[0].clickPoint)
    }

    func testSecureTypingWritesNoStep() throws {
        describer.field = FocusedField(label: "Password", security: .secure, element: nil)
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        typeAndReturn("s")
        let (manifest, sessionFolder) = stop()
        XCTAssertTrue(manifest.steps.isEmpty)
        assertNothingTyped("s", in: sessionFolder)
    }

    func testUnknownFieldAtStartWritesNoStep() throws {
        describer.fields = [FocusedField(label: "Name", security: .unknown, element: nil)]
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        typeAndReturn("John")
        let (manifest, sessionFolder) = stop()
        XCTAssertTrue(manifest.steps.isEmpty)
        assertNothingTyped("John", in: sessionFolder)
    }

    func testFieldTurningSecureByBurstEndWritesNoStep() throws {
        describer.fields = [FocusedField(label: "Name", security: .notSecure, element: nil),
                            FocusedField(label: "Password", security: .secure, element: nil)]
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        typeAndReturn("John")
        let (manifest, sessionFolder) = stop()
        XCTAssertTrue(manifest.steps.isEmpty)
        assertNothingTyped("John", in: sessionFolder)
    }

    func testFocusMovingToAnotherFieldWritesNoStep() throws {
        describer.fields = [FocusedField(label: "Name", security: .notSecure, element: AXUIElementCreateApplication(1)),
                            FocusedField(label: "Name", security: .notSecure, element: AXUIElementCreateApplication(2))]
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        typeAndReturn("John")
        let (manifest, sessionFolder) = stop()
        XCTAssertTrue(manifest.steps.isEmpty)
        assertNothingTyped("John", in: sessionFolder)
    }

    func testSameNonSecureFieldWritesTypingStep() throws {
        let element = AXUIElementCreateApplication(1)
        describer.fields = [FocusedField(label: "Name", security: .notSecure, element: element),
                            FocusedField(label: "Name", security: .notSecure, element: element)]
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        typeAndReturn("John")
        waitForSteps(1)
        let steps = stop().0.steps
        XCTAssertEqual(steps.map(\.kind), [.typing])
        XCTAssertEqual(steps.first?.caption, #"Type "John" in **Name**"#)
    }

    func testTypingEndedBySupersedingClickIsWrittenBeforeTheClick() throws {
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        manager.handle(.click(CGPoint(x: 150, y: 160)))
        manager.handle(.key(KeyInput(characters: "J", baseCharacters: "j", keyCode: 0, modifiers: [.shift], isSecure: false)))
        manager.handle(.click(CGPoint(x: 151, y: 161), clickCount: 2))   // a double-click, inside the delay
        waitForSteps(2)
        XCTAssertEqual(stop().0.steps.map(\.kind), [.typing, .click])
    }

    func testTypingBetweenTwoSeparateClicksIsWrittenBetweenThem() throws {
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        manager.handle(.click(CGPoint(x: 150, y: 160)))
        manager.handle(.key(KeyInput(characters: "J", baseCharacters: "j", keyCode: 0, modifiers: [.shift], isSecure: false)))
        manager.handle(.click(CGPoint(x: 170, y: 170)))   // inside the first click's delay, elsewhere
        XCTAssertEqual(stop().0.steps.map(\.kind), [.click, .typing, .click])
    }

    // Finding 1: a Tab or click reaches the app before the burst ends, so a read issued after
    // it sees the next field. Every read issued while typing answers A, any later one B.
    func testTypingStepWrittenWhenBurstEndsOnTab() throws {
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        typeIntoFieldThenLeave("John")
        manager.handle(.key(KeyInput(characters: "\t", baseCharacters: "\t", keyCode: 48, modifiers: [], isSecure: false)))
        waitForSteps(1)
        let steps = stop().0.steps
        XCTAssertEqual(steps.map(\.kind), [.typing])
        XCTAssertEqual(steps.first?.caption, #"Type "John" in **Name**"#)
    }

    func testTypingStepWrittenBeforeClickWhenBurstEndsOnClick() throws {
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        typeIntoFieldThenLeave("John")
        manager.handle(.click(CGPoint(x: 150, y: 160)))
        waitForSteps(2)
        let steps = stop().0.steps
        XCTAssertEqual(steps.map(\.kind), [.typing, .click])
        XCTAssertEqual(steps.first?.caption, #"Type "John" in **Name**"#)
    }

    /// Types `text` into field A, waits until every per-key read has run, then makes later
    /// reads answer field B — what a real Tab or click does to the focused element.
    private func typeIntoFieldThenLeave(_ text: String) {
        let fieldA = AXUIElementCreateApplication(1)
        describer.field = FocusedField(label: "Name", security: .notSecure, element: fieldA)
        let readsDone = expectation(description: "\(text.count) focus reads")
        describer.onRead = { if $0 == text.count { readsDone.fulfill() } }
        for ch in text {
            manager.handle(.key(KeyInput(characters: String(ch), baseCharacters: String(ch), keyCode: 0, modifiers: [], isSecure: false)))
        }
        wait(for: [readsDone], timeout: 5)
        describer.onRead = nil
        describer.passBoundary(to: FocusedField(label: "Email", security: .notSecure, element: AXUIElementCreateApplication(2)))
    }

    // Finding 2: a superseded click's slot must still wait for the step before it.
    func testSupersededClickWaitsForInFlightManualStep() throws {
        let secondClick = CGPoint(x: 151.5, y: 161.25)
        images.delay = { $0 == .screenContaining(secondClick) ? 0 : 1 }
        _ = try manager.start(settings: settings { $0.scope = .screen }, area: nil)
        manager.captureManualStep()                       // capture held for 1 s
        manager.handle(.click(CGPoint(x: 150.5, y: 160.25)))
        manager.handle(.click(secondClick, clickCount: 2)) // supersedes the first click
        XCTAssertEqual(stop().0.steps.map(\.kind), [.manual, .click])
    }

    // Finding 3: the tap sees Clipr's own hotkeys before Carbon handles them.
    func testOwnHotkeyIsNotATypingStep() throws {
        let stepHotkey = HotkeyBinding(keyCode: 1, modifiers: HotkeyBinding.Modifier.control.rawValue | HotkeyBinding.Modifier.option.rawValue)
        _ = try manager.start(settings: settings { $0.typingSteps = true; $0.stepHotkey = stepHotkey }, area: nil,
                              ignoredKeys: [.defaultCapture, .defaultAdvancedMode, stepHotkey])
        manager.handle(.key(KeyInput(characters: "ß", baseCharacters: "s", keyCode: 1, modifiers: [.control, .option], isSecure: false)))
        manager.handle(.key(KeyInput(characters: "@", baseCharacters: "2", keyCode: 19, modifiers: [.command, .shift], isSecure: false)))
        XCTAssertTrue(stop().0.steps.isEmpty)
    }

    func testShortcutNotMatchingAHotkeyIsStillAStep() throws {
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil, ignoredKeys: [.defaultCapture])
        manager.handle(.key(KeyInput(characters: "2", baseCharacters: "2", keyCode: 19, modifiers: [.command], isSecure: false)))
        waitForSteps(1)
        XCTAssertEqual(stop().0.steps.map(\.caption), ["Press **⌘2**"])
    }

    // Finding 5: only keys that open or extend a burst read the focused field.
    func testNonPrintableKeysDoNotReadTheFocusedField() throws {
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        for code: UInt16 in [123, 124, 125, 126, 53] {   // arrows, Escape
            manager.handle(.key(KeyInput(characters: "", baseCharacters: "", keyCode: code, modifiers: [], isSecure: false)))
        }
        manager.handle(.key(KeyInput(characters: "s", baseCharacters: "s", keyCode: 1, modifiers: [.command], isSecure: false)))
        manager.handle(.key(KeyInput(characters: "a", baseCharacters: "a", keyCode: 0, modifiers: [], isSecure: false)))
        manager.handle(.key(KeyInput(characters: "", baseCharacters: "", keyCode: 51, modifiers: [], isSecure: false)))  // ⌫
        _ = stop()
        XCTAssertEqual(describer.readCount, 1)   // just the "a"
    }

    // Finding 7: pausing throws a half-typed burst away instead of writing it.
    func testPauseDiscardsOpenTypingBurst() throws {
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        for ch in "Jo" {
            manager.handle(.key(KeyInput(characters: String(ch), baseCharacters: String(ch), keyCode: 0, modifiers: [], isSecure: false)))
        }
        manager.isPaused = true
        // Past the idle timeout: the cancelled idle check must not write the burst while paused.
        let idle = expectation(description: "idle timeout passes")
        idle.isInverted = true
        wait(for: [idle], timeout: KeystrokeAggregator.idleTimeout + 0.3)
        manager.isPaused = false
        let (manifest, sessionFolder) = stop()
        XCTAssertTrue(manifest.steps.isEmpty)
        assertNothingTyped("Jo", in: sessionFolder)
    }

    private func typeAndReturn(_ text: String) {
        for ch in text {
            manager.handle(.key(KeyInput(characters: String(ch), baseCharacters: String(ch), keyCode: 0, modifiers: [], isSecure: false)))
        }
        manager.handle(.key(KeyInput(characters: "\r", baseCharacters: "\r", keyCode: 36, modifiers: [], isSecure: false)))
    }

    /// No screenshot on disk, and nothing typed in the manifest if one was written.
    private func assertNothingTyped(_ text: String, in sessionFolder: URL, file: StaticString = #filePath, line: UInt = #line) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: sessionFolder.path)) ?? []
        XCTAssertFalse(files.contains { $0.hasPrefix("Step_") && $0.hasSuffix(".png") }, "step PNG written: \(files)", file: file, line: line)
        let manifestURL = sessionFolder.appendingPathComponent("session.json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            XCTAssertFalse(SessionManifestStore.load(from: sessionFolder).steps.contains { $0.kind == .typing }, file: file, line: line)
            XCTAssertFalse(((try? String(contentsOf: manifestURL)) ?? "").contains(text), file: file, line: line)
        }
    }

    // L4: a click made just before Pause is captured at Pause, not after the delay.
    func testPauseCapturesPendingClickImmediately() throws {
        images.delay = { _ in 0 }
        _ = try manager.start(settings: settings { $0.captureDelay = 2 }, area: nil)
        let captured = expectation(description: "captured at pause")
        manager.onStepCaptured = { if $0 == 1 { captured.fulfill() } }
        manager.handle(.click(CGPoint(x: 150, y: 160)))
        manager.isPaused = true
        wait(for: [captured], timeout: 1)   // well before the 2 s delay would have fired it
        XCTAssertEqual(stop().0.steps.map(\.kind), [.click])
    }

    // L3: movement from before a pause doesn't lead into the first click after Resume.
    func testPauseDropsCursorTrail() throws {
        _ = try manager.start(settings: settings { $0.cursorTrail = true }, area: nil)
        manager.handle(.mouseMoved(CGPoint(x: 110, y: 110)))
        manager.handle(.mouseMoved(CGPoint(x: 120, y: 110)))
        manager.isPaused = true
        manager.isPaused = false
        manager.handle(.mouseMoved(CGPoint(x: 300, y: 200)))
        manager.handle(.click(CGPoint(x: 310, y: 210)))
        waitForSteps(1)
        let (manifest, sessionFolder) = stop()
        let annotations = StorageManager(baseFolder: folder).loadAnnotations(rawURL: sessionFolder.appendingPathComponent(manifest.steps[0].file))
        for annotation in annotations {
            if case .freehand(let pts) = annotation.kind { XCTAssertFalse(pts.contains(CGPoint(x: 10, y: 290)), "pre-pause point in trail") }
        }
    }

    func testPausedIgnoresEverything() throws {
        _ = try manager.start(settings: settings(), area: nil)
        manager.isPaused = true
        manager.handle(.click(CGPoint(x: 150, y: 160)))
        XCTAssertTrue(stop().0.steps.isEmpty)
    }

    func testStopFlushesPendingClickAndTypingBeforeCompleting() throws {
        _ = try manager.start(settings: settings { $0.captureDelay = 2; $0.typingSteps = true }, area: nil)
        manager.handle(.click(CGPoint(x: 150, y: 160)))           // still inside its 2 s delay
        manager.handle(.key(KeyInput(characters: "a", baseCharacters: "a", keyCode: 0, modifiers: [], isSecure: false)))
        manager.handle(.ownClick)                                 // the Stop button itself
        let steps = stop().0.steps
        XCTAssertEqual(steps.map(\.kind), [.click, .typing])
    }

    func testOwnClickNeverMakesAStep() throws {
        _ = try manager.start(settings: settings(), area: nil)
        manager.handle(.ownClick)
        XCTAssertTrue(stop().0.steps.isEmpty)
    }

    // M2: Window scope captures the window under the click, captioned with its app.
    func testWindowScopeCapturesClickedWindow() throws {
        let palette = ClickedWindow(windowID: 42, ownerPID: 7, layer: 3, appName: "Pixelmator")
        _ = try manager.start(settings: settings { $0.scope = .window }, area: nil)
        manager.handle(.click(CGPoint(x: 150, y: 160), window: palette))
        waitForSteps(1)
        let steps = stop().0.steps
        XCTAssertEqual(images.targets, [.window(palette)])
        XCTAssertEqual(steps.first?.caption, "Click **Save** in Pixelmator")
        XCTAssertEqual(steps.first?.appName, "Pixelmator")
    }

    func testWindowScopeClickOnDockFallsBackToFrontmostWindow() throws {
        let dock = ClickedWindow(windowID: 3, ownerPID: 9, layer: ClickedWindow.dockLayer, appName: "Dock")
        _ = try manager.start(settings: settings { $0.scope = .window }, area: nil)
        manager.handle(.click(CGPoint(x: 150, y: 160), window: dock))
        waitForSteps(1)
        let steps = stop().0.steps
        XCTAssertEqual(images.targets, [.frontmostWindow])
        XCTAssertEqual(steps.first?.appName, "Safari")
    }

    func testFallbackCaptureHasNoMarkerOrClickPoint() throws {
        images.marksClick = false
        _ = try manager.start(settings: settings { $0.zoomOnClick = true; $0.cursorTrail = true }, area: nil)
        manager.handle(.mouseMoved(CGPoint(x: 120, y: 120)))
        manager.handle(.click(CGPoint(x: 150, y: 160)))
        waitForSteps(1)
        let (manifest, sessionFolder) = stop()
        XCTAssertNil(manifest.steps[0].clickPoint)
        XCTAssertNil(manifest.steps[0].zoomFile)
        XCTAssertTrue(StorageManager(baseFolder: folder).loadAnnotations(rawURL: sessionFolder.appendingPathComponent(manifest.steps[0].file)).isEmpty)
    }

    // M8: a typing step in Screen scope captures the display the field is on, not the pointer's.
    func testScreenScopeTypingCapturesTheFieldsDisplay() throws {
        describer.field = FocusedField(label: "Name", security: .notSecure, element: nil,
                                       frame: CGRect(x: 2000, y: 400, width: 200, height: 20))
        _ = try manager.start(settings: settings { $0.scope = .screen; $0.typingSteps = true }, area: nil)
        typeAndReturn("John")
        waitForSteps(1)
        _ = stop()
        XCTAssertEqual(images.targets, [.screenContaining(CGPoint(x: 2100, y: 410))])
    }

    // A field whose midpoint is off every display (here, below them) still captures the display
    // showing most of it, rather than dropping the step.
    func testScreenScopeTypingInAFieldWithAnOffscreenMidpointIsKept() throws {
        describer.field = FocusedField(label: "Name", security: .notSecure, element: nil,
                                       frame: CGRect(x: 2000, y: 1060, width: 200, height: 100))
        _ = try manager.start(settings: settings { $0.scope = .screen; $0.typingSteps = true }, area: nil)
        typeAndReturn("John")
        waitForSteps(1)
        _ = stop()
        XCTAssertEqual(images.targets, [.screenContaining(CGPoint(x: 2100, y: 1070))])
    }

    func testScreenScopeShortcutCapturesTheDisplayOfTheLastClick() throws {
        _ = try manager.start(settings: settings { $0.scope = .screen; $0.typingSteps = true; $0.captureDelay = 0 }, area: nil)
        manager.handle(.click(CGPoint(x: 2100, y: 410)))
        waitForSteps(1)
        manager.handle(.key(KeyInput(characters: "s", baseCharacters: "s", keyCode: 1, modifiers: [.command], isSecure: false)))
        waitForSteps(2)
        _ = stop()
        XCTAssertEqual(images.targets, [.screenContaining(CGPoint(x: 2100, y: 410)), .screenContaining(CGPoint(x: 2100, y: 410))])
    }

    func testFixedAreaTargetsArea() throws {
        let area = CGRect(x: 100, y: 100, width: 400, height: 300)
        _ = try manager.start(settings: settings { $0.scope = .fixedArea }, area: area)
        manager.handle(.click(CGPoint(x: 150, y: 160)))
        waitForSteps(1)
        _ = stop()
        XCTAssertEqual(images.targets, [.area(area)])
    }

    func testManualStepHasNoCaptionOrMarker() throws {
        _ = try manager.start(settings: settings(), area: nil)
        manager.captureManualStep()
        waitForSteps(1)
        let (manifest, sessionFolder) = stop()
        XCTAssertEqual(manifest.steps[0].kind, .manual)
        XCTAssertNil(manifest.steps[0].caption)
        XCTAssertTrue(StorageManager(baseFolder: folder).loadAnnotations(rawURL: sessionFolder.appendingPathComponent(manifest.steps[0].file)).isEmpty)
    }
}
