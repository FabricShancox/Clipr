// Tests/ClipprTests/ClickCaptureManagerTests.swift
import XCTest
@testable import Clipr

private final class FakeSource: SessionEventSource {
    var onEvent: ((SessionEvent) -> Void)?
    var startedWith: SessionEventOptions?
    func start(options: SessionEventOptions) throws { startedWith = options }
    func stop() {}
}

private final class FakeImages: StepImageSource {
    var ownWindowIDs: Set<CGWindowID> = []
    var targets: [CaptureTarget] = []
    let origin = CGPoint(x: 100, y: 100)
    func capture(_ target: CaptureTarget, showsCursor: Bool) async throws -> CapturedFrame? {
        await MainActor.run { self.targets.append(target) }
        let image = testImage(width: 400, height: 300) { NSColor.white.set(); NSRect(x: 0, y: 0, width: 400, height: 300).fill() }
        return CapturedFrame(image: image, origin: origin, appName: "Safari")
    }
}

private final class FakeDescriber: ClickDescribing {
    var target: ClickTarget? = ClickTarget(role: "AXButton", subrole: nil, label: "Save", menuPath: [])
    var field: (String?, Bool) = ("Name", false)
    func describe(at point: CGPoint) async -> ClickTarget? { target }
    func focusedField() async -> (label: String?, isSecure: Bool) { field }
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

    func testTypingDisabledWithoutInputMonitoring() throws {
        manager = ClickCaptureManager(storage: StorageManager(baseFolder: folder), imageSource: images, describer: describer,
                                      eventSource: source, accessibilityGranted: { true }, inputMonitoringGranted: { false })
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        XCTAssertEqual(source.startedWith?.keys, false)
        XCTAssertTrue(manager.typingUnavailable)
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
        manager.handle(.mouseMoved(CGPoint(x: 160, y: 120)))
        manager.handle(.click(CGPoint(x: 170, y: 130)))
        waitForSteps(1)
        let (manifest, sessionFolder) = stop()
        XCTAssertEqual(manifest.steps.count, 1)
        XCTAssertEqual(manifest.steps[0].clickPoint, CGPoint(x: 70, y: 30))
        let annotations = StorageManager(baseFolder: folder).loadAnnotations(rawURL: sessionFolder.appendingPathComponent(manifest.steps[0].file))
        let trail = annotations.first { if case .freehand = $0.kind { return true }; return false }
        guard case .freehand(let pts)? = trail?.kind else { return XCTFail("no trail") }
        XCTAssertEqual(pts.count, 4)  // 2 moves + 1 move + final click point
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
        describer.field = ("Password", true)
        _ = try manager.start(settings: settings { $0.typingSteps = true }, area: nil)
        manager.handle(.key(KeyInput(characters: "s", baseCharacters: "s", keyCode: 0, modifiers: [], isSecure: false)))
        manager.handle(.key(KeyInput(characters: "\r", baseCharacters: "\r", keyCode: 36, modifiers: [], isSecure: false)))
        let (manifest, sessionFolder) = stop()
        XCTAssertTrue(manifest.steps.isEmpty)
        let json = (try? String(contentsOf: sessionFolder.appendingPathComponent("session.json"))) ?? ""
        XCTAssertFalse(json.contains("\"s\""))
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
