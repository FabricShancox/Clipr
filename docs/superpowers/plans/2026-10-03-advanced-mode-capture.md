# Advanced Mode Capture Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Advanced Mode a per-session manifest plus click markers, cursor trail, zoom crops, auto captions, typing steps, capture scope/delay and a step hotkey — each configurable in Preferences — so sessions produce guide-ready steps.

**Architecture:** Pure, unit-tested units (settings, manifest, trail, keystroke aggregation, captions, geometry, annotation factory, zoom) are composed by a rewritten `ClickCaptureManager` that receives events from a `SessionEventTap`, captures through a `StepImageSource`, and writes PNG → annotations sidecar → zoom → `session.json`. Markers are ordinary `AnnotationObject`s, so the existing editor and renderer handle them.

**Tech Stack:** Swift 5.10, SwiftPM, AppKit + SwiftUI, ScreenCaptureKit, ApplicationServices (AX, CGEventTap), Carbon (secure input, hotkeys), XCTest.

**Spec:** `docs/superpowers/specs/2026-10-03-advanced-mode-capture-design.md`

## Global Constraints

- Platform floor: macOS 14 (`Package.swift` `platforms: [.macOS(.v14)]`). No new package dependencies.
- Build: `swift build`; tests: `swift test` from repo root. App bundle: `./Scripts/build-app.sh`.
- Defaults: click marker on (ring), auto captions on, cursor trail off, zoom off, typing steps off, scope Window, delay 0.3 s (range 0–2 s, effective minimum 0.2 s), step hotkey unset.
- Ring 36×36 pt, stroke 3; dot 14×14 pt, stroke 7; color = `EditorView.swatchColors[5]` (the editor's default red).
- Trail: drop points < 8 pt from previous kept point, max 300 points (drop oldest), stroke 2, 60% alpha.
- Zoom: 400×300 pt crop, shifted to stay inside the image, file `Step_NN_zoom.png`.
- Caption labels/text: trimmed, whitespace collapsed, truncated to 60 characters with `…`, `*` and `"` backslash-escaped.
- Typing burst ends on 1.0 s idle, Return, Tab, or click. Secure bursts are discarded entirely.
- AX messaging timeout 0.25 s; caption wait capped at 0.5 s at capture time.
- Write order per step: PNG → annotations sidecar → zoom PNG → manifest entry.
- `AnnotationObject.frame` and `.freehand` points are in **renderer space: image points, bottom-left origin, y up**. Everything computed from screen positions is top-left first and must be flipped with `StepGeometry.toRenderer`.
- Settings are snapshotted at session start.
- Deliberate simplification vs. spec: a typing step under Screen scope uses the display under the cursor (the spec's fallback) rather than the focused element's display.
- Code comments follow the repo's style: explain *why*, in full sentences, at the declaration.

## Review Focus

1. **Clicks on a secondary display left of / above the primary (negative global origin) or on Retina** — the marker must land exactly on the click. Pinned in Task 6 (`testNegativeOriginSecondaryDisplay`, `testRetinaStepReloadsInPointSpace`).
2. **Rapid double-clicks / clicks faster than the delay** — must produce one step, with both clicks' trail points kept. Pinned in Task 12 (`testRapidClicksCoalesceIntoOneStepKeepingTrail`).
3. **Typing into a password field, then clicking** — nothing about the typed text may reach disk or a caption. Pinned in Task 4 (`testSecureBurstIsDiscardedEvenIfLaterKeysAreNotSecure`) and Task 12 (`testSecureTypingWritesNoStep`).
4. **Pressing Stop while a click capture is still within its delay, or mid-typing** — the user expects that last step to be kept, and nothing written after the Review window opens. Pinned in Task 12 (`testStopFlushesPendingClickAndTypingBeforeCompleting`).
5. **Old sessions (no `session.json`) and folders containing editor `_edited.png` / `_annotations.json` and `_zoom.png` files** — Review must list exactly the raw steps. Pinned in Task 2 (`testReconstructionIgnoresDerivedFiles`, `testMissingManifestReconstructsFromPNGs`).

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `Sources/Clipr/Settings/AdvancedModeSettings.swift` | Create | Settings struct, defaults, tolerant decoding |
| `Sources/Clipr/Settings/SettingsStore.swift` | Modify | `advancedMode` property |
| `Sources/Clipr/AdvancedMode/SessionManifest.swift` | Create | `SessionManifest`, `StepRecord`, `SessionManifestStore` (IO + reconciliation) |
| `Sources/Clipr/AdvancedMode/CursorTrailRecorder.swift` | Create | Pure trail accumulator |
| `Sources/Clipr/AdvancedMode/KeystrokeAggregator.swift` | Create | `KeyInput`, `KeyModifiers`, `TypingEvent`, pure aggregator |
| `Sources/Clipr/AdvancedMode/CaptionFormatter.swift` | Create | `ClickTarget`, pure caption text |
| `Sources/Clipr/AdvancedMode/StepGeometry.swift` | Create | Pure coordinate mapping |
| `Sources/Clipr/AdvancedMode/StepAnnotationFactory.swift` | Create | Pure marker/trail annotations |
| `Sources/Clipr/AdvancedMode/StepZoom.swift` | Create | Zoom crop rect + crop |
| `Sources/Clipr/Storage/FilenameGenerator.swift` | Modify | `zoomName(fromStep:)` |
| `Sources/Clipr/Storage/StorageManager.swift` | Modify | `saveStepZoom` |
| `Sources/Clipr/AdvancedMode/ClickDescriber.swift` | Create | AX adapter (`ClickDescribing` protocol + live impl) |
| `Sources/Clipr/AdvancedMode/SessionEventTap.swift` | Create | CGEventTap → `SessionEvent` (`SessionEventSource` protocol + live impl) |
| `Sources/Clipr/AdvancedMode/StepImageSource.swift` | Create | Per-scope capture (`StepImageSource` protocol + live impl) |
| `Sources/Clipr/Capture/CaptureManager.swift` | Modify | Make `captureFullScreen`/`snapshotScreens` internal |
| `Sources/Clipr/AdvancedMode/ClickCaptureManager.swift` | Rewrite | Session coordinator |
| `Sources/Clipr/AdvancedMode/AreaPicker.swift` | Create | One-shot area selection for Fixed area scope |
| `Sources/Clipr/AdvancedMode/AdvancedModeCoordinator.swift` | Modify | Start/stop API, manifest-backed review |
| `Sources/Clipr/AdvancedMode/AdvancedModeControlPanel.swift` | Modify | Warning row |
| `Sources/Clipr/AdvancedMode/ReviewWindowController.swift`, `ReviewView.swift` | Modify | Steps from manifest, show captions |
| `Sources/Clipr/AppDelegate.swift` | Modify | Wiring, step hotkey, area pick |
| `Sources/Clipr/PreferencesUI/PreferencesView.swift` | Modify | Advanced Mode section |
| `docs/superpowers/checklists/advanced-mode-capture-manual.md` | Create | Manual test checklist |
| `Tests/ClipprTests/*Tests.swift` | Create | One test file per pure unit + manager |

---

### Task 1: AdvancedModeSettings

**Files:**
- Create: `Sources/Clipr/Settings/AdvancedModeSettings.swift`
- Modify: `Sources/Clipr/Settings/SettingsStore.swift`
- Test: `Tests/ClipprTests/AdvancedModeSettingsTests.swift`

**Interfaces:**
- Consumes: `HotkeyBinding` (existing, `Codable, Equatable`).
- Produces: `struct AdvancedModeSettings: Codable, Equatable` with fields `clickMarker: Bool`, `markerStyle: MarkerStyle` (`.ring`, `.dot`), `autoCaptions: Bool`, `cursorTrail: Bool`, `zoomOnClick: Bool`, `typingSteps: Bool`, `scope: Scope` (`.window`, `.screen`, `.fixedArea`), `captureDelay: TimeInterval`, `stepHotkey: HotkeyBinding?`; `static let default`; `var effectiveDelay: TimeInterval`. `SettingsStore.advancedMode: AdvancedModeSettings`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClipprTests/AdvancedModeSettingsTests.swift
import XCTest
@testable import Clipr

final class AdvancedModeSettingsTests: XCTestCase {
    func testDefaultsAreTunedForGuides() {
        let s = AdvancedModeSettings.default
        XCTAssertTrue(s.clickMarker)
        XCTAssertEqual(s.markerStyle, .ring)
        XCTAssertTrue(s.autoCaptions)
        XCTAssertFalse(s.cursorTrail)
        XCTAssertFalse(s.zoomOnClick)
        XCTAssertFalse(s.typingSteps)
        XCTAssertEqual(s.scope, .window)
        XCTAssertEqual(s.captureDelay, 0.3, accuracy: 0.0001)
        XCTAssertNil(s.stepHotkey)
    }

    func testEffectiveDelayIsClampedBetweenDebounceFloorAndMax() {
        var s = AdvancedModeSettings.default
        s.captureDelay = 0
        XCTAssertEqual(s.effectiveDelay, 0.2, accuracy: 0.0001)
        s.captureDelay = 5
        XCTAssertEqual(s.effectiveDelay, 2, accuracy: 0.0001)
        s.captureDelay = 0.7
        XCTAssertEqual(s.effectiveDelay, 0.7, accuracy: 0.0001)
    }

    func testDecodingMissingKeysFallsBackToDefaults() throws {
        let json = #"{"cursorTrail": true}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(AdvancedModeSettings.self, from: json)
        XCTAssertTrue(s.cursorTrail)
        XCTAssertTrue(s.clickMarker)
        XCTAssertEqual(s.scope, .window)
        XCTAssertEqual(s.captureDelay, 0.3, accuracy: 0.0001)
    }

    func testSettingsStoreRoundTrip() {
        let defaults = UserDefaults(suiteName: "ClipprTests.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.advancedMode, .default)
        var custom = AdvancedModeSettings.default
        custom.scope = .fixedArea
        custom.markerStyle = .dot
        custom.stepHotkey = HotkeyBinding(keyCode: 1, modifiers: HotkeyBinding.Modifier.option.rawValue)
        store.advancedMode = custom
        XCTAssertEqual(SettingsStore(defaults: defaults).advancedMode, custom)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AdvancedModeSettingsTests`
Expected: compile failure, "cannot find 'AdvancedModeSettings' in scope".

- [ ] **Step 3: Implement**

```swift
// Sources/Clipr/Settings/AdvancedModeSettings.swift
import Foundation

/// Everything Advanced Mode can be configured to do, stored as one value so a session can
/// snapshot it at start — changing Preferences mid-session applies to the next session, never
/// half of the current one.
struct AdvancedModeSettings: Codable, Equatable {
    enum MarkerStyle: String, Codable, CaseIterable { case ring, dot }
    enum Scope: String, Codable, CaseIterable { case window, screen, fixedArea }

    var clickMarker = true
    var markerStyle: MarkerStyle = .ring
    var autoCaptions = true
    var cursorTrail = false
    var zoomOnClick = false
    var typingSteps = false
    var scope: Scope = .window
    var captureDelay: TimeInterval = 0.3
    var stepHotkey: HotkeyBinding?

    static let `default` = AdvancedModeSettings()

    /// Never below 0.2 s: that's the debounce that merges a double-click into one step, so a
    /// 0 s delay would otherwise turn every double-click into two.
    var effectiveDelay: TimeInterval { min(max(captureDelay, 0.2), 2) }

    init() {}

    /// Hand-written so a key added in a later version — or missing from an older stored value —
    /// falls back to its default instead of failing the whole decode and resetting every setting.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AdvancedModeSettings.default
        clickMarker = try c.decodeIfPresent(Bool.self, forKey: .clickMarker) ?? d.clickMarker
        markerStyle = try c.decodeIfPresent(MarkerStyle.self, forKey: .markerStyle) ?? d.markerStyle
        autoCaptions = try c.decodeIfPresent(Bool.self, forKey: .autoCaptions) ?? d.autoCaptions
        cursorTrail = try c.decodeIfPresent(Bool.self, forKey: .cursorTrail) ?? d.cursorTrail
        zoomOnClick = try c.decodeIfPresent(Bool.self, forKey: .zoomOnClick) ?? d.zoomOnClick
        typingSteps = try c.decodeIfPresent(Bool.self, forKey: .typingSteps) ?? d.typingSteps
        scope = try c.decodeIfPresent(Scope.self, forKey: .scope) ?? d.scope
        captureDelay = try c.decodeIfPresent(TimeInterval.self, forKey: .captureDelay) ?? d.captureDelay
        stepHotkey = try c.decodeIfPresent(HotkeyBinding.self, forKey: .stepHotkey)
    }
}
```

In `SettingsStore.swift` add to `Key`: `static let advancedMode = "advancedMode"` and the property after `copyStyle`:

```swift
    /// All Advanced Mode options — see `AdvancedModeSettings`.
    var advancedMode: AdvancedModeSettings {
        get { decoded(Key.advancedMode) ?? .default }
        set { encode(newValue, forKey: Key.advancedMode) }
    }
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter AdvancedModeSettingsTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/Settings/AdvancedModeSettings.swift Sources/Clipr/Settings/SettingsStore.swift Tests/ClipprTests/AdvancedModeSettingsTests.swift
git commit -m "feat: add Advanced Mode settings model"
```

---

### Task 2: Session manifest

**Files:**
- Create: `Sources/Clipr/AdvancedMode/SessionManifest.swift`
- Modify: `Sources/Clipr/Storage/FilenameGenerator.swift` (add `zoomName`)
- Test: `Tests/ClipprTests/SessionManifestTests.swift`

**Interfaces:**
- Produces:
  - `struct StepRecord: Codable, Identifiable, Equatable { enum Kind: String, Codable { case click, typing, manual }; let id: UUID; var file: String; var kind: Kind; var caption: String?; var clickPoint: CGPoint?; var zoomFile: String?; var appName: String?; var capturedAt: Date }`
  - `struct SessionManifest: Codable, Equatable { var version: Int; var createdAt: Date; var steps: [StepRecord]; init(createdAt: Date, steps: [StepRecord] = []) }`
  - `enum SessionManifestStore { static let fileName = "session.json"; static func save(_: SessionManifest, in folder: URL) throws; static func load(from folder: URL) -> SessionManifest; static func rawStepFiles(in folder: URL) -> [String] }`
  - `FilenameGenerator.zoomName(fromStep: String) -> String` (`"Step_03.png"` → `"Step_03_zoom.png"`)

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClipprTests/SessionManifestTests.swift
import XCTest
@testable import Clipr

final class SessionManifestTests: XCTestCase {
    var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func touch(_ name: String) {
        FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data([0]))
    }

    private func record(_ file: String, caption: String? = nil) -> StepRecord {
        StepRecord(id: UUID(), file: file, kind: .click, caption: caption, clickPoint: CGPoint(x: 1, y: 2),
                   zoomFile: nil, appName: "Safari", capturedAt: Date(timeIntervalSince1970: 1000))
    }

    func testRoundTripPreservesOrderAndFields() throws {
        touch("Step_01.png"); touch("Step_02.png")
        let manifest = SessionManifest(createdAt: Date(timeIntervalSince1970: 0),
                                       steps: [record("Step_02.png", caption: "B"), record("Step_01.png", caption: "A")])
        try SessionManifestStore.save(manifest, in: folder)
        XCTAssertEqual(SessionManifestStore.load(from: folder), manifest)
    }

    func testMissingManifestReconstructsFromPNGs() {
        touch("Step_10.png"); touch("Step_2.png"); touch("Step_01.png")
        let loaded = SessionManifestStore.load(from: folder)
        XCTAssertEqual(loaded.steps.map(\.file), ["Step_01.png", "Step_2.png", "Step_10.png"])
        XCTAssertTrue(loaded.steps.allSatisfy { $0.kind == .manual && $0.caption == nil })
    }

    func testCorruptManifestReconstructs() throws {
        touch("Step_01.png")
        try Data("not json".utf8).write(to: folder.appendingPathComponent(SessionManifestStore.fileName))
        XCTAssertEqual(SessionManifestStore.load(from: folder).steps.map(\.file), ["Step_01.png"])
    }

    func testReconstructionIgnoresDerivedFiles() {
        touch("Step_01.png"); touch("Step_01_edited.png"); touch("Step_01_zoom.png")
        touch("Step_01_annotations.json"); touch(".DS_Store")
        XCTAssertEqual(SessionManifestStore.load(from: folder).steps.map(\.file), ["Step_01.png"])
    }

    func testOrphanPNGsAreAppendedAndMissingFilesDropped() throws {
        touch("Step_01.png"); touch("Step_03.png")
        let manifest = SessionManifest(createdAt: Date(), steps: [record("Step_02.png"), record("Step_01.png", caption: "keep")])
        try SessionManifestStore.save(manifest, in: folder)
        let loaded = SessionManifestStore.load(from: folder)
        XCTAssertEqual(loaded.steps.map(\.file), ["Step_01.png", "Step_03.png"])
        XCTAssertEqual(loaded.steps[0].caption, "keep")
        XCTAssertEqual(loaded.steps[1].kind, .manual)
    }

    func testZoomName() {
        XCTAssertEqual(FilenameGenerator.zoomName(fromStep: "Step_03.png"), "Step_03_zoom.png")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SessionManifestTests`
Expected: compile failure, "cannot find 'StepRecord' in scope".

- [ ] **Step 3: Implement**

In `FilenameGenerator.swift`, after `stepName(index:)`:

```swift
    /// The close-up crop saved next to a step when "Zoom on click" is on.
    static func zoomName(fromStep stepFilename: String) -> String {
        guard stepFilename.hasSuffix(".png") else { return stepFilename + "_zoom.png" }
        return "\(stepFilename.dropLast(4))_zoom.png"
    }
```

```swift
// Sources/Clipr/AdvancedMode/SessionManifest.swift
import Foundation
import CoreGraphics

/// One step of an Advanced Mode session as recorded in `session.json`.
struct StepRecord: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case click, typing, manual }

    let id: UUID
    /// Filename relative to the session folder, e.g. "Step_03.png".
    var file: String
    var kind: Kind
    var caption: String?
    /// Image point space, top-left origin. `nil` when the click fell outside the captured image
    /// or the step had no click.
    var clickPoint: CGPoint?
    var zoomFile: String?
    var appName: String?
    var capturedAt: Date
}

/// `steps` order is display order, so steps can be reordered later without renaming files.
struct SessionManifest: Codable, Equatable {
    var version: Int
    var createdAt: Date
    var steps: [StepRecord]

    init(createdAt: Date, steps: [StepRecord] = []) {
        version = 1
        self.createdAt = createdAt
        self.steps = steps
    }
}

enum SessionManifestStore {
    static let fileName = "session.json"

    static func save(_ manifest: SessionManifest, in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: folder.appendingPathComponent(fileName), options: .atomic)
    }

    /// Always returns a manifest that matches the folder's contents: entries whose PNG is gone are
    /// dropped and raw step PNGs with no entry are appended as `.manual` steps without captions.
    /// A missing or unreadable `session.json` (sessions recorded before the manifest existed, or a
    /// failed write) therefore still yields every step instead of an empty session.
    static func load(from folder: URL) -> SessionManifest {
        let onDisk = rawStepFiles(in: folder)
        var manifest = decoded(from: folder) ?? SessionManifest(createdAt: creationDate(of: folder))
        let present = Set(onDisk)
        manifest.steps.removeAll { !present.contains($0.file) }
        let listed = Set(manifest.steps.map(\.file))
        for file in onDisk where !listed.contains(file) {
            manifest.steps.append(StepRecord(
                id: UUID(), file: file, kind: .manual, caption: nil, clickPoint: nil,
                zoomFile: nil, appName: nil, capturedAt: manifest.createdAt
            ))
        }
        return manifest
    }

    /// Raw step PNGs only, in natural order ("Step_2" before "Step_10"). The editor writes
    /// `_edited.png` previews and zoom writes `_zoom.png` next to them; neither is a step.
    static func rawStepFiles(in folder: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .filter { $0.hasPrefix("Step_") && $0.lowercased().hasSuffix(".png")
                && !$0.hasSuffix("_edited.png") && !$0.hasSuffix("_zoom.png") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func decoded(from folder: URL) -> SessionManifest? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SessionManifest.self, from: data)
    }

    private static func creationDate(of folder: URL) -> Date {
        (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }
}
```

Note: `.iso8601` drops sub-second precision; the round-trip test uses whole-second dates for that reason.

- [ ] **Step 4: Run tests**

Run: `swift test --filter SessionManifestTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/SessionManifest.swift Sources/Clipr/Storage/FilenameGenerator.swift Tests/ClipprTests/SessionManifestTests.swift
git commit -m "feat: add Advanced Mode session manifest with reconstruction"
```

---

### Task 3: CursorTrailRecorder

**Files:**
- Create: `Sources/Clipr/AdvancedMode/CursorTrailRecorder.swift`
- Test: `Tests/ClipprTests/CursorTrailRecorderTests.swift`

**Interfaces:**
- Produces: `struct CursorTrailRecorder { static let minDistance: CGFloat = 8; static let maxPoints = 300; private(set) var points: [CGPoint]; mutating func add(_ point: CGPoint); mutating func drain() -> [CGPoint] }`. Points are global, top-left origin.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClipprTests/CursorTrailRecorderTests.swift
import XCTest
@testable import Clipr

final class CursorTrailRecorderTests: XCTestCase {
    func testDropsPointsCloserThanMinDistance() {
        var r = CursorTrailRecorder()
        r.add(CGPoint(x: 0, y: 0))
        r.add(CGPoint(x: 3, y: 4))   // distance 5 — dropped
        r.add(CGPoint(x: 6, y: 8))   // distance 10 from (0,0) — kept
        XCTAssertEqual(r.points, [CGPoint(x: 0, y: 0), CGPoint(x: 6, y: 8)])
    }

    func testCapDropsOldest() {
        var r = CursorTrailRecorder()
        for i in 0..<(CursorTrailRecorder.maxPoints + 5) {
            r.add(CGPoint(x: CGFloat(i) * 10, y: 0))
        }
        XCTAssertEqual(r.points.count, CursorTrailRecorder.maxPoints)
        XCTAssertEqual(r.points.first, CGPoint(x: 50, y: 0))
    }

    func testDrainReturnsAndResets() {
        var r = CursorTrailRecorder()
        r.add(CGPoint(x: 0, y: 0)); r.add(CGPoint(x: 20, y: 0))
        XCTAssertEqual(r.drain().count, 2)
        XCTAssertTrue(r.points.isEmpty)
        r.add(CGPoint(x: 1, y: 1))
        XCTAssertEqual(r.points, [CGPoint(x: 1, y: 1)])  // no distance filter against drained points
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CursorTrailRecorderTests`
Expected: compile failure, "cannot find 'CursorTrailRecorder' in scope".

- [ ] **Step 3: Implement**

```swift
// Sources/Clipr/AdvancedMode/CursorTrailRecorder.swift
import CoreGraphics

/// The cursor's path since the last step, in global top-left coordinates. Mouse-moved events
/// arrive at display refresh rate; thinning to points at least `minDistance` apart and capping
/// the count keeps the resulting freehand annotation light without changing its visible shape.
struct CursorTrailRecorder {
    static let minDistance: CGFloat = 8
    static let maxPoints = 300

    private(set) var points: [CGPoint] = []

    mutating func add(_ point: CGPoint) {
        if let last = points.last, hypot(point.x - last.x, point.y - last.y) < Self.minDistance { return }
        points.append(point)
        if points.count > Self.maxPoints { points.removeFirst(points.count - Self.maxPoints) }
    }

    mutating func drain() -> [CGPoint] {
        defer { points = [] }
        return points
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter CursorTrailRecorderTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/CursorTrailRecorder.swift Tests/ClipprTests/CursorTrailRecorderTests.swift
git commit -m "feat: add cursor trail recorder"
```

---

### Task 4: KeystrokeAggregator

**Files:**
- Create: `Sources/Clipr/AdvancedMode/KeystrokeAggregator.swift`
- Test: `Tests/ClipprTests/KeystrokeAggregatorTests.swift`

**Interfaces:**
- Produces:
  - `struct KeyModifiers: OptionSet, Equatable { static let control, option, shift, command }`
  - `struct KeyInput: Equatable { var characters: String; var baseCharacters: String; var keyCode: UInt16; var modifiers: KeyModifiers; var isSecure: Bool }` (`characters` = as typed; `baseCharacters` = `charactersIgnoringModifiers`)
  - `enum TypingEvent: Equatable { case text(String); case shortcut(String) }`
  - `struct KeystrokeAggregator { static let idleTimeout: TimeInterval = 1.0; var hasPendingBurst: Bool { get }; mutating func handle(_ key: KeyInput, at time: Date) -> [TypingEvent]; mutating func endBurst() -> TypingEvent?; mutating func idleCheck(now: Date) -> TypingEvent? }`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClipprTests/KeystrokeAggregatorTests.swift
import XCTest
@testable import Clipr

final class KeystrokeAggregatorTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)

    private func key(_ c: String, code: UInt16 = 0, mods: KeyModifiers = [], secure: Bool = false) -> KeyInput {
        KeyInput(characters: c, baseCharacters: c.lowercased(), keyCode: code, modifiers: mods, isSecure: secure)
    }

    private func type(_ s: String, into a: inout KeystrokeAggregator) {
        for ch in s { _ = a.handle(key(String(ch)), at: t0) }
    }

    func testIdleEndsBurst() {
        var a = KeystrokeAggregator()
        type("John", into: &a)
        XCTAssertNil(a.idleCheck(now: t0.addingTimeInterval(0.5)))
        XCTAssertEqual(a.idleCheck(now: t0.addingTimeInterval(1.0)), .text("John"))
        XCTAssertFalse(a.hasPendingBurst)
    }

    func testReturnAndTabEndBurst() {
        var a = KeystrokeAggregator()
        type("hi", into: &a)
        XCTAssertEqual(a.handle(key("\r", code: 36), at: t0), [.text("hi")])
        type("yo", into: &a)
        XCTAssertEqual(a.handle(key("\t", code: 48), at: t0), [.text("yo")])
        XCTAssertEqual(a.handle(key("\r", code: 36), at: t0), [])  // empty burst emits nothing
    }

    func testExplicitEndForClick() {
        var a = KeystrokeAggregator()
        type("abc", into: &a)
        XCTAssertEqual(a.endBurst(), .text("abc"))
        XCTAssertNil(a.endBurst())
    }

    func testBackspaceRemovesLastCharacterAndIsSafeWhenEmpty() {
        var a = KeystrokeAggregator()
        _ = a.handle(key("\u{7F}", code: 51), at: t0)
        type("Jonn", into: &a)
        _ = a.handle(key("\u{7F}", code: 51), at: t0)
        XCTAssertEqual(a.endBurst(), .text("Jon"))
    }

    func testArrowsAndEscapeAreIgnored() {
        var a = KeystrokeAggregator()
        type("a", into: &a)
        _ = a.handle(key("\u{F702}", code: 123), at: t0)
        _ = a.handle(key("\u{1B}", code: 53), at: t0)
        XCTAssertEqual(a.endBurst(), .text("a"))
    }

    func testShortcutEndsBurstAndUsesGlyphOrder() {
        var a = KeystrokeAggregator()
        type("x", into: &a)
        let events = a.handle(key("s", mods: [.command, .shift, .control, .option]), at: t0)
        XCTAssertEqual(events, [.text("x"), .shortcut("⌃⌥⇧⌘S")])
    }

    func testShiftAloneIsTyping() {
        var a = KeystrokeAggregator()
        _ = a.handle(key("J", mods: [.shift]), at: t0)
        XCTAssertEqual(a.endBurst(), .text("J"))
    }

    func testSecureBurstIsDiscardedEvenIfLaterKeysAreNotSecure() {
        var a = KeystrokeAggregator()
        _ = a.handle(key("p", secure: true), at: t0)
        _ = a.handle(key("w"), at: t0)
        XCTAssertNil(a.endBurst())
        type("ok", into: &a)   // next burst is clean again
        XCTAssertEqual(a.endBurst(), .text("ok"))
    }

    func testSecureBurstEndedByReturnEmitsNothing() {
        var a = KeystrokeAggregator()
        _ = a.handle(key("p", secure: true), at: t0)
        XCTAssertEqual(a.handle(key("\r", code: 36), at: t0), [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter KeystrokeAggregatorTests`
Expected: compile failure, "cannot find 'KeystrokeAggregator' in scope".

- [ ] **Step 3: Implement**

```swift
// Sources/Clipr/AdvancedMode/KeystrokeAggregator.swift
import Foundation

struct KeyModifiers: OptionSet, Equatable {
    let rawValue: Int
    static let control = KeyModifiers(rawValue: 1 << 0)
    static let option = KeyModifiers(rawValue: 1 << 1)
    static let shift = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)
}

/// One key press, already decoded off the event tap so this file stays free of CGEvent.
struct KeyInput: Equatable {
    /// As typed (with Shift/Option applied).
    var characters: String
    /// `charactersIgnoringModifiers`, used to name shortcuts.
    var baseCharacters: String
    var keyCode: UInt16
    var modifiers: KeyModifiers
    /// macOS secure input was on, or the focused element is a password field.
    var isSecure: Bool
}

enum TypingEvent: Equatable {
    case text(String)
    case shortcut(String)
}

/// Groups key presses into "typed X" bursts and "pressed ⌘S" shortcuts for typing steps.
/// Time is passed in rather than read, so the idle rule is testable.
struct KeystrokeAggregator {
    static let idleTimeout: TimeInterval = 1.0

    private enum KeyCode {
        static let returnKey: UInt16 = 36, keypadEnter: UInt16 = 76, tab: UInt16 = 48
        static let delete: UInt16 = 51, escape: UInt16 = 53, forwardDelete: UInt16 = 117
        static let arrows: ClosedRange<UInt16> = 123...126
    }

    private var buffer = ""
    /// Once any key of a burst was secure the whole burst is thrown away — even characters typed
    /// before secure input switched on — so no fragment of a password can ever be stored.
    private var isSecureBurst = false
    private var lastKeyAt: Date?

    var hasPendingBurst: Bool { !buffer.isEmpty || isSecureBurst }

    mutating func handle(_ key: KeyInput, at time: Date) -> [TypingEvent] {
        if key.modifiers.contains(.command) || key.modifiers.contains(.control) {
            var events: [TypingEvent] = []
            if let ended = endBurst() { events.append(ended) }
            events.append(.shortcut(Self.glyphs(key.modifiers) + key.baseCharacters.uppercased()))
            return events
        }
        switch key.keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter, KeyCode.tab:
            return endBurst().map { [$0] } ?? []
        case KeyCode.escape, KeyCode.forwardDelete, KeyCode.arrows:
            return []
        default:
            break
        }
        lastKeyAt = time
        if key.isSecure { isSecureBurst = true }
        if key.keyCode == KeyCode.delete {
            if !buffer.isEmpty { buffer.removeLast() }
            return []
        }
        buffer += key.characters.filter(Self.isPrintable)
        return []
    }

    mutating func endBurst() -> TypingEvent? {
        defer { buffer = ""; isSecureBurst = false; lastKeyAt = nil }
        guard !isSecureBurst, !buffer.isEmpty else { return nil }
        return .text(buffer)
    }

    mutating func idleCheck(now: Date) -> TypingEvent? {
        guard let lastKeyAt, now.timeIntervalSince(lastKeyAt) >= Self.idleTimeout else { return nil }
        return endBurst()
    }

    private static func glyphs(_ m: KeyModifiers) -> String {
        (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "")
            + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "")
    }

    /// Excludes control characters and the private-use range (U+F700–U+F8FF) AppKit uses for
    /// function and arrow keys.
    private static func isPrintable(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value) }
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter KeystrokeAggregatorTests`
Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/KeystrokeAggregator.swift Tests/ClipprTests/KeystrokeAggregatorTests.swift
git commit -m "feat: add keystroke aggregator for typing steps"
```

---

### Task 5: CaptionFormatter

**Files:**
- Create: `Sources/Clipr/AdvancedMode/CaptionFormatter.swift`
- Test: `Tests/ClipprTests/CaptionFormatterTests.swift`

**Interfaces:**
- Produces:
  - `struct ClickTarget: Equatable { var role: String?; var subrole: String?; var label: String?; var menuPath: [String] }` (role strings are AX constants like `"AXButton"`)
  - `enum CaptionFormatter { static let maxLength = 60; static func click(_ target: ClickTarget?, appName: String?) -> String; static func typing(_ text: String, fieldLabel: String?) -> String; static func shortcut(_ keys: String) -> String; static func clean(_ raw: String?) -> String? }`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClipprTests/CaptionFormatterTests.swift
import XCTest
@testable import Clipr

final class CaptionFormatterTests: XCTestCase {
    private func t(_ role: String?, _ label: String?, menu: [String] = []) -> ClickTarget {
        ClickTarget(role: role, subrole: nil, label: label, menuPath: menu)
    }

    func testMenuItemUsesPath() {
        XCTAssertEqual(CaptionFormatter.click(t("AXMenuItem", "Export…", menu: ["File", "Export…"]), appName: "Pages"),
                       "Choose **File ▸ Export…**")
    }

    func testButtonLikeRoles() {
        for role in ["AXButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXTab"] {
            XCTAssertEqual(CaptionFormatter.click(t(role, "Save"), appName: "Safari"), "Click **Save** in Safari", role)
        }
    }

    func testTextFieldRoles() {
        for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
            XCTAssertEqual(CaptionFormatter.click(t(role, "Name"), appName: "Safari"), "Click the **Name** field", role)
        }
    }

    func testLink() {
        XCTAssertEqual(CaptionFormatter.click(t("AXLink", "Pricing"), appName: "Safari"), "Click the **Pricing** link")
    }

    func testOtherLabelledRole() {
        XCTAssertEqual(CaptionFormatter.click(t("AXImage", "Logo"), appName: "Finder"), "Click **Logo** in Finder")
    }

    func testFallbacks() {
        XCTAssertEqual(CaptionFormatter.click(nil, appName: "Finder"), "Click in **Finder**")
        XCTAssertEqual(CaptionFormatter.click(t("AXButton", "   "), appName: "Finder"), "Click in **Finder**")
        XCTAssertEqual(CaptionFormatter.click(nil, appName: nil), "Click")
        XCTAssertEqual(CaptionFormatter.click(t("AXButton", "Save"), appName: nil), "Click **Save**")
    }

    func testTypingAndShortcut() {
        XCTAssertEqual(CaptionFormatter.typing("John", fieldLabel: "Name"), #"Type "John" in **Name**"#)
        XCTAssertEqual(CaptionFormatter.typing("John", fieldLabel: nil), #"Type "John""#)
        XCTAssertEqual(CaptionFormatter.shortcut("⌘S"), "Press **⌘S**")
    }

    func testCleanCollapsesWhitespaceTruncatesAndEscapes() {
        XCTAssertEqual(CaptionFormatter.clean("  Save\n\n  As  "), "Save As")
        XCTAssertEqual(CaptionFormatter.clean(String(repeating: "a", count: 70)), String(repeating: "a", count: 60) + "…")
        XCTAssertEqual(CaptionFormatter.clean(#"**Bold** "q""#), #"\*\*Bold\*\* \"q\""#)
        XCTAssertNil(CaptionFormatter.clean(" \n "))
        XCTAssertNil(CaptionFormatter.clean(nil))
    }

    func testTypingTextIsCleanedToo() {
        XCTAssertEqual(CaptionFormatter.typing(#"say "hi""#, fieldLabel: nil), #"Type "say \"hi\"""#)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CaptionFormatterTests`
Expected: compile failure, "cannot find 'ClickTarget' in scope".

- [ ] **Step 3: Implement**

```swift
// Sources/Clipr/AdvancedMode/CaptionFormatter.swift
import Foundation

/// What Accessibility reported under a click, reduced to the fields captions need.
struct ClickTarget: Equatable {
    var role: String?
    var subrole: String?
    var label: String?
    /// For menu items: titles from the menu bar item down to the clicked item.
    var menuPath: [String] = []
}

/// Guide-style step captions. Bold uses Markdown `**` so the export sub-project can render it;
/// `clean` escapes `*` and `"` in anything taken from the UI so a label can't break that markup.
enum CaptionFormatter {
    static let maxLength = 60

    private static let fieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    static func click(_ target: ClickTarget?, appName: String?) -> String {
        let app = clean(appName)
        if let target, target.role == "AXMenuItem" {
            let path = target.menuPath.compactMap { clean($0) }
            if !path.isEmpty { return "Choose **\(path.joined(separator: " ▸ "))**" }
        }
        guard let target, let label = clean(target.label) else {
            return app.map { "Click in **\($0)**" } ?? "Click"
        }
        let role = target.role ?? ""
        if fieldRoles.contains(role) { return "Click the **\(label)** field" }
        if role == "AXLink" { return "Click the **\(label)** link" }
        // Buttons, pop-ups, checkboxes, tabs and every other labelled role share this wording.
        return app.map { "Click **\(label)** in \($0)" } ?? "Click **\(label)**"
    }

    static func typing(_ text: String, fieldLabel: String?) -> String {
        let typed = clean(text) ?? ""
        if let field = clean(fieldLabel) { return "Type \"\(typed)\" in **\(field)**" }
        return "Type \"\(typed)\""
    }

    static func shortcut(_ keys: String) -> String { "Press **\(keys)**" }

    /// Trim, collapse runs of whitespace/newlines to one space, truncate to `maxLength` characters
    /// (before escaping, so escapes never get cut in half), then escape. `nil` if nothing remains.
    static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let collapsed = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        let truncated = collapsed.count > maxLength ? String(collapsed.prefix(maxLength)) + "…" : collapsed
        return truncated.replacingOccurrences(of: "*", with: "\\*").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter CaptionFormatterTests`
Expected: 9 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/CaptionFormatter.swift Tests/ClipprTests/CaptionFormatterTests.swift
git commit -m "feat: add guide-style caption formatter"
```

---

### Task 6: StepGeometry

**Files:**
- Create: `Sources/Clipr/AdvancedMode/StepGeometry.swift`
- Test: `Tests/ClipprTests/StepGeometryTests.swift`

**Interfaces:**
- Produces: `enum StepGeometry { static func imagePoint(global: CGPoint, captureOrigin: CGPoint, imageSize: CGSize) -> CGPoint?; static func toRenderer(_ p: CGPoint, imageHeight: CGFloat) -> CGPoint; static func globalTopLeftFrame(ofScreenFrame frame: CGRect, primaryScreenHeight: CGFloat) -> CGRect; static func globalTopLeftRect(viewLocal rect: CGRect, screenFrame: CGRect, primaryScreenHeight: CGFloat) -> CGRect }`

"Global top-left" = Quartz display space (`CGEvent.location`, `kCGWindowBounds`): origin at the primary display's top-left, y down. `NSScreen.frame` is AppKit space: origin at primary's bottom-left, y up.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClipprTests/StepGeometryTests.swift
import XCTest
@testable import Clipr

final class StepGeometryTests: XCTestCase {
    func testOffsetWindow() {
        let p = StepGeometry.imagePoint(global: CGPoint(x: 150, y: 260), captureOrigin: CGPoint(x: 100, y: 200),
                                        imageSize: CGSize(width: 400, height: 300))
        XCTAssertEqual(p, CGPoint(x: 50, y: 60))
    }

    func testNegativeOriginSecondaryDisplay() {
        // Display to the left of and above the primary: global coordinates are negative.
        let p = StepGeometry.imagePoint(global: CGPoint(x: -1500, y: -100), captureOrigin: CGPoint(x: -1920, y: -300),
                                        imageSize: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(p, CGPoint(x: 420, y: 200))
    }

    func testOutsideImageIsNil() {
        let size = CGSize(width: 100, height: 100)
        XCTAssertNil(StepGeometry.imagePoint(global: CGPoint(x: 99, y: 250), captureOrigin: .zero, imageSize: size))
        XCTAssertNil(StepGeometry.imagePoint(global: CGPoint(x: -1, y: 5), captureOrigin: .zero, imageSize: size))
        XCTAssertNil(StepGeometry.imagePoint(global: CGPoint(x: 100, y: 5), captureOrigin: .zero, imageSize: size))
    }

    func testToRendererFlipsY() {
        XCTAssertEqual(StepGeometry.toRenderer(CGPoint(x: 10, y: 30), imageHeight: 100), CGPoint(x: 10, y: 70))
    }

    func testScreenFrameConversion() {
        // Primary 1000 tall. A display above the primary in AppKit space (y 1000...1600).
        let frame = CGRect(x: 0, y: 1000, width: 800, height: 600)
        XCTAssertEqual(StepGeometry.globalTopLeftFrame(ofScreenFrame: frame, primaryScreenHeight: 1000),
                       CGRect(x: 0, y: -600, width: 800, height: 600))
    }

    func testViewLocalRectConversion() {
        let screen = CGRect(x: 1440, y: 0, width: 1000, height: 800)
        let r = StepGeometry.globalTopLeftRect(viewLocal: CGRect(x: 10, y: 20, width: 30, height: 40),
                                               screenFrame: screen, primaryScreenHeight: 900)
        XCTAssertEqual(r, CGRect(x: 1450, y: 120, width: 30, height: 40))
    }

    /// The spec requires proving a saved Retina step reloads in the point space markers are
    /// computed in — otherwise every marker on a 2x display lands at half/double position.
    func testRetinaStepReloadsInPointSpace() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let storage = StorageManager(baseFolder: folder)
        let image = testImage(width: 200, height: 100, scale: 2) {
            NSColor.blue.set(); NSRect(x: 0, y: 0, width: 200, height: 100).fill()
        }
        let url = try storage.saveStep(image, index: 1, in: folder)
        let reloaded = try XCTUnwrap(NSImage(contentsOf: url))
        XCTAssertEqual(reloaded.size, CGSize(width: 200, height: 100))
        XCTAssertEqual(reloaded.pixelScale, 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StepGeometryTests`
Expected: compile failure, "cannot find 'StepGeometry' in scope".

- [ ] **Step 3: Implement**

```swift
// Sources/Clipr/AdvancedMode/StepGeometry.swift
import CoreGraphics

/// Coordinate conversions between where things happen on screen and where they belong in a
/// step image. Step images are sized in points (see `NSImage+PixelScale.swift`), so no pixel
/// scale appears here — only origins and the y-axis flip.
enum StepGeometry {
    /// `global` and `captureOrigin` are Quartz global points (top-left origin, y down). Returns the
    /// point inside the image (top-left origin), or `nil` if it falls outside it.
    static func imagePoint(global: CGPoint, captureOrigin: CGPoint, imageSize: CGSize) -> CGPoint? {
        let p = CGPoint(x: global.x - captureOrigin.x, y: global.y - captureOrigin.y)
        guard p.x >= 0, p.y >= 0, p.x < imageSize.width, p.y < imageSize.height else { return nil }
        return p
    }

    /// `AnnotationObject` geometry is bottom-left origin, y up (see `AnnotationRenderer.flatten`).
    static func toRenderer(_ p: CGPoint, imageHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: imageHeight - p.y)
    }

    /// An `NSScreen.frame` (AppKit space) as a Quartz global rect.
    static func globalTopLeftFrame(ofScreenFrame frame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryScreenHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// A rect from `CaptureOverlayView` (view-local points, top-left, view filling `screenFrame`)
    /// as a Quartz global rect.
    static func globalTopLeftRect(viewLocal rect: CGRect, screenFrame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        let screen = globalTopLeftFrame(ofScreenFrame: screenFrame, primaryScreenHeight: primaryScreenHeight)
        return rect.offsetBy(dx: screen.minX, dy: screen.minY)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter StepGeometryTests`
Expected: 7 tests pass. If `testRetinaStepReloadsInPointSpace` fails, stop: the marker math assumes point-sized reloads and the spec requires this to hold — report it rather than adjusting the test.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/StepGeometry.swift Tests/ClipprTests/StepGeometryTests.swift
git commit -m "feat: add step coordinate geometry"
```

---

### Task 7: StepAnnotationFactory

**Files:**
- Create: `Sources/Clipr/AdvancedMode/StepAnnotationFactory.swift`
- Test: `Tests/ClipprTests/StepAnnotationFactoryTests.swift`

**Interfaces:**
- Consumes: `StepGeometry.imagePoint`, `StepGeometry.toRenderer`, `AdvancedModeSettings.MarkerStyle`, `AnnotationObject(id:kind:frame:color:strokeWidth:)`, `EditorView.swatchColors`.
- Produces: `enum StepAnnotationFactory { static var markerColor: RGBAColor; static func marker(at imagePoint: CGPoint, style: AdvancedModeSettings.MarkerStyle, imageSize: CGSize) -> AnnotationObject; static func trail(globalPoints: [CGPoint], captureOrigin: CGPoint, imageSize: CGSize) -> AnnotationObject? }` — `imagePoint` is top-left image space; output is renderer space.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClipprTests/StepAnnotationFactoryTests.swift
import XCTest
@testable import Clipr

final class StepAnnotationFactoryTests: XCTestCase {
    let size = CGSize(width: 400, height: 300)

    func testRingIsCenteredInRendererSpace() {
        let a = StepAnnotationFactory.marker(at: CGPoint(x: 100, y: 50), style: .ring, imageSize: size)
        XCTAssertEqual(a.kind, .ellipse)
        // top-left y 50 → renderer y 250; 36 pt ring centred there.
        XCTAssertEqual(a.frame, CGRect(x: 82, y: 232, width: 36, height: 36))
        XCTAssertEqual(a.strokeWidth, 3)
        XCTAssertEqual(a.color, StepAnnotationFactory.markerColor)
    }

    func testDotIsSmallAndFilledByStroke() {
        let a = StepAnnotationFactory.marker(at: CGPoint(x: 100, y: 50), style: .dot, imageSize: size)
        XCTAssertEqual(a.frame, CGRect(x: 93, y: 243, width: 14, height: 14))
        XCTAssertEqual(a.strokeWidth, 7)
    }

    func testTrailMapsClipsAndFlips() throws {
        let origin = CGPoint(x: 1000, y: 500)
        let points = [CGPoint(x: 1010, y: 510), CGPoint(x: 900, y: 510), CGPoint(x: 1050, y: 560)]
        let a = try XCTUnwrap(StepAnnotationFactory.trail(globalPoints: points, captureOrigin: origin, imageSize: size))
        guard case .freehand(let pts) = a.kind else { return XCTFail("not freehand") }
        XCTAssertEqual(pts, [CGPoint(x: 10, y: 290), CGPoint(x: 50, y: 240)])  // off-image point dropped
        XCTAssertEqual(a.frame, CGRect(x: 10, y: 240, width: 40, height: 50))
        XCTAssertEqual(a.strokeWidth, 2)
        XCTAssertEqual(a.color.alpha, 0.6, accuracy: 0.001)
    }

    func testTrailNeedsTwoPointsInside() {
        XCTAssertNil(StepAnnotationFactory.trail(globalPoints: [CGPoint(x: 5, y: 5)], captureOrigin: .zero, imageSize: size))
        XCTAssertNil(StepAnnotationFactory.trail(globalPoints: [CGPoint(x: 5, y: 5), CGPoint(x: -5, y: 5)],
                                                 captureOrigin: .zero, imageSize: size))
    }

    func testMarkerRendersWhereClicked() {
        // Integration: flatten a marker onto a white image and check the ring's left edge pixel.
        let base = testImage(width: 400, height: 300) { NSColor.white.set(); NSRect(x: 0, y: 0, width: 400, height: 300).fill() }
        let ring = StepAnnotationFactory.marker(at: CGPoint(x: 100, y: 50), style: .ring, imageSize: size)
        let flat = AnnotationRenderer.flatten(base: base, annotations: [ring])
        let rep = NSBitmapImageRep(cgImage: flat.bitmap!)
        // Bitmap rows are top-down: the ring's left edge is at x≈82, top-left y 50.
        let c = rep.colorAt(x: 83, y: 50)!
        XCTAssertGreaterThan(c.redComponent, 0.8)
        XCTAssertLessThan(c.greenComponent, 0.5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StepAnnotationFactoryTests`
Expected: compile failure, "cannot find 'StepAnnotationFactory' in scope".

- [ ] **Step 3: Implement**

```swift
// Sources/Clipr/AdvancedMode/StepAnnotationFactory.swift
import CoreGraphics
import Foundation

/// Builds the click marker and cursor trail as ordinary annotations, so they open in the editor
/// as editable shapes rather than being burned into the step's pixels.
enum StepAnnotationFactory {
    static let ringDiameter: CGFloat = 36
    static let ringStroke: CGFloat = 3
    static let dotDiameter: CGFloat = 14
    static let trailStroke: CGFloat = 2
    static let trailAlpha: CGFloat = 0.6

    /// The editor's default colour, so a marker looks like something the user could have drawn.
    static var markerColor: RGBAColor { EditorView.swatchColors[5] }

    static func marker(at imagePoint: CGPoint, style: AdvancedModeSettings.MarkerStyle, imageSize: CGSize) -> AnnotationObject {
        let center = StepGeometry.toRenderer(imagePoint, imageHeight: imageSize.height)
        let diameter = style == .ring ? ringDiameter : dotDiameter
        // A dot is an ellipse stroked as thick as its radius, which fills it without needing a
        // new filled-shape annotation kind.
        let stroke = style == .ring ? ringStroke : dotDiameter / 2
        return AnnotationObject(
            id: UUID(), kind: .ellipse,
            frame: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter),
            color: markerColor, strokeWidth: stroke
        )
    }

    static func trail(globalPoints: [CGPoint], captureOrigin: CGPoint, imageSize: CGSize) -> AnnotationObject? {
        let points = globalPoints
            .compactMap { StepGeometry.imagePoint(global: $0, captureOrigin: captureOrigin, imageSize: imageSize) }
            .map { StepGeometry.toRenderer($0, imageHeight: imageSize.height) }
        guard points.count >= 2 else { return nil }
        var color = markerColor
        color.alpha = trailAlpha
        return AnnotationObject(id: UUID(), kind: .freehand(points), frame: boundingBox(points), color: color, strokeWidth: trailStroke)
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter StepAnnotationFactoryTests`
Expected: 5 tests pass. If `testMarkerRendersWhereClicked` fails on the pixel check, print `rep.colorAt` for x 80…86 and y 48…52 to find the actual edge before changing anything; a mismatch means the renderer-space assumption is wrong.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/StepAnnotationFactory.swift Tests/ClipprTests/StepAnnotationFactoryTests.swift
git commit -m "feat: build click marker and trail annotations"
```

---

### Task 8: Zoom crop

**Files:**
- Create: `Sources/Clipr/AdvancedMode/StepZoom.swift`
- Modify: `Sources/Clipr/Storage/StorageManager.swift` (add `saveStepZoom`)
- Test: `Tests/ClipprTests/StepZoomTests.swift`

**Interfaces:**
- Consumes: `CaptureGeometry.cropped(_:to:)`, `FilenameGenerator.zoomName(fromStep:)`.
- Produces: `enum StepZoom { static let size = CGSize(width: 400, height: 300); static func cropRect(centeredOn p: CGPoint, imageSize: CGSize) -> CGRect; static func image(from image: NSImage, centeredOn p: CGPoint) -> NSImage? }`; `StorageManager.saveStepZoom(_ image: NSImage, stepURL: URL) throws -> URL`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClipprTests/StepZoomTests.swift
import XCTest
@testable import Clipr

final class StepZoomTests: XCTestCase {
    func testCenteredWhenRoomAllowsIt() {
        XCTAssertEqual(StepZoom.cropRect(centeredOn: CGPoint(x: 500, y: 400), imageSize: CGSize(width: 1000, height: 800)),
                       CGRect(x: 300, y: 250, width: 400, height: 300))
    }

    func testShiftedNotShrunkAtEdges() {
        let size = CGSize(width: 1000, height: 800)
        XCTAssertEqual(StepZoom.cropRect(centeredOn: CGPoint(x: 10, y: 10), imageSize: size),
                       CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(StepZoom.cropRect(centeredOn: CGPoint(x: 990, y: 790), imageSize: size),
                       CGRect(x: 600, y: 500, width: 400, height: 300))
    }

    func testSmallImageUsesWholeDimension() {
        XCTAssertEqual(StepZoom.cropRect(centeredOn: CGPoint(x: 100, y: 50), imageSize: CGSize(width: 300, height: 120)),
                       CGRect(x: 0, y: 0, width: 300, height: 120))
    }

    func testCropKeepsRetinaPixelsAndSavesNextToStep() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = testImage(width: 1000, height: 800, scale: 2) { NSColor.green.set(); NSRect(x: 0, y: 0, width: 1000, height: 800).fill() }
        let zoom = try XCTUnwrap(StepZoom.image(from: image, centeredOn: CGPoint(x: 500, y: 400)))
        XCTAssertEqual(zoom.size, CGSize(width: 400, height: 300))
        XCTAssertEqual(zoom.pixelScale, 2)
        let storage = StorageManager(baseFolder: folder)
        let step = try storage.saveStep(image, index: 3, in: folder)
        let url = try storage.saveStepZoom(zoom, stepURL: step)
        XCTAssertEqual(url.lastPathComponent, "Step_03_zoom.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StepZoomTests`
Expected: compile failure, "cannot find 'StepZoom' in scope".

- [ ] **Step 3: Implement**

```swift
// Sources/Clipr/AdvancedMode/StepZoom.swift
import Cocoa

/// The close-up saved beside a step when "Zoom on click" is on — for guides where the full
/// window is too large to read the control that was clicked.
enum StepZoom {
    static let size = CGSize(width: 400, height: 300)

    /// Top-left image space. Shifted to stay inside the image rather than shrunk, so every zoom
    /// in a session has the same proportions; only an image smaller than the crop limits it.
    static func cropRect(centeredOn p: CGPoint, imageSize: CGSize) -> CGRect {
        let w = min(size.width, imageSize.width), h = min(size.height, imageSize.height)
        let x = min(max(p.x - w / 2, 0), imageSize.width - w)
        let y = min(max(p.y - h / 2, 0), imageSize.height - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func image(from image: NSImage, centeredOn p: CGPoint) -> NSImage? {
        CaptureGeometry.cropped(image, to: cropRect(centeredOn: p, imageSize: image.size))?.image
    }
}
```

In `StorageManager.swift`, after `saveStep`:

```swift
    /// Overwrites rather than suffixing: a zoom belongs to exactly one step file.
    func saveStepZoom(_ image: NSImage, stepURL: URL) throws -> URL {
        let name = FilenameGenerator.zoomName(fromStep: stepURL.lastPathComponent)
        return try write(image, to: stepURL.deletingLastPathComponent().appendingPathComponent(name), overwrite: true)
    }
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter StepZoomTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/StepZoom.swift Sources/Clipr/Storage/StorageManager.swift Tests/ClipprTests/StepZoomTests.swift
git commit -m "feat: add zoom-on-click crop"
```

---

### Task 9: ClickDescriber (Accessibility)

**Files:**
- Create: `Sources/Clipr/AdvancedMode/ClickDescriber.swift`

No unit test: AX needs a live, trusted process. Covered by the manual checklist (Task 14). The protocol exists so Task 12 can inject a fake.

**Interfaces:**
- Consumes: `ClickTarget`.
- Produces: `protocol ClickDescribing: AnyObject { func describe(at point: CGPoint) async -> ClickTarget?; func focusedField() async -> (label: String?, isSecure: Bool) }`; `final class ClickDescriber: ClickDescribing`.

- [ ] **Step 1: Implement**

```swift
// Sources/Clipr/AdvancedMode/ClickDescriber.swift
import ApplicationServices
import Foundation

protocol ClickDescribing: AnyObject {
    /// What's under `point` (Quartz global). `nil` if Accessibility can't say.
    func describe(at point: CGPoint) async -> ClickTarget?
    /// The focused element's label (for "Type … in **Name**") and whether it's a password field.
    func focusedField() async -> (label: String?, isSecure: Bool)
}

/// Reads the UI under a click through Accessibility. Runs on its own serial queue with a short
/// messaging timeout: a hung target app would otherwise block for AX's default ~6 s, and this
/// must never run on the main thread where the event tap lives (a blocked tap gets disabled).
final class ClickDescriber: ClickDescribing {
    private let queue = DispatchQueue(label: "Clipr.ClickDescriber")
    private let systemWide = AXUIElementCreateSystemWide()

    init() {
        AXUIElementSetMessagingTimeout(systemWide, 0.25)
    }

    func describe(at point: CGPoint) async -> ClickTarget? {
        await withCheckedContinuation { continuation in
            queue.async { [systemWide] in
                var element: AXUIElement?
                guard AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
                      let element else { return continuation.resume(returning: nil) }
                continuation.resume(returning: Self.target(for: element))
            }
        }
    }

    func focusedField() async -> (label: String?, isSecure: Bool) {
        await withCheckedContinuation { continuation in
            queue.async { [systemWide] in
                guard let focused = Self.element(systemWide, kAXFocusedUIElementAttribute) else {
                    return continuation.resume(returning: (nil, false))
                }
                let isSecure = Self.string(focused, kAXSubroleAttribute) == "AXSecureTextField"
                continuation.resume(returning: (Self.label(of: focused, role: Self.string(focused, kAXRoleAttribute)), isSecure))
            }
        }
    }

    private static let fieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    private static func target(for element: AXUIElement) -> ClickTarget {
        let role = string(element, kAXRoleAttribute)
        var target = ClickTarget(role: role, subrole: string(element, kAXSubroleAttribute), label: label(of: element, role: role))
        if role == kAXMenuItemRole as String { target.menuPath = menuPath(from: element) }
        return target
    }

    /// Never a text field's value: that's whatever the user typed, possibly private.
    private static func label(of element: AXUIElement, role: String?) -> String? {
        let candidates = [kAXTitleAttribute, kAXDescriptionAttribute, kAXPlaceholderValueAttribute as String, kAXHelpAttribute]
        for attribute in candidates {
            if let s = string(element, attribute), !s.trimmingCharacters(in: .whitespaces).isEmpty { return s }
        }
        if let titleElement = Self.element(element, kAXTitleUIElementAttribute),
           let s = string(titleElement, kAXValueAttribute) { return s }
        if let role, !fieldRoles.contains(role), role != "AXSecureTextField", let s = string(element, kAXValueAttribute) { return s }
        return nil
    }

    /// Menu bar item → … → clicked item, by walking up through AXMenu parents.
    private static func menuPath(from item: AXUIElement) -> [String] {
        var titles: [String] = []
        var current: AXUIElement? = item
        var depth = 0
        while let el = current, depth < 10 {
            let role = string(el, kAXRoleAttribute)
            if role == kAXMenuItemRole as String || role == kAXMenuBarItemRole as String,
               let title = string(el, kAXTitleAttribute), !title.isEmpty {
                titles.append(title)
            }
            if role == kAXMenuBarItemRole as String { break }
            current = element(el, kAXParentAttribute)
            depth += 1
        }
        return titles.reversed()
    }

    private static func string(_ el: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func element(_ el: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete, no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Clipr/AdvancedMode/ClickDescriber.swift
git commit -m "feat: describe clicked UI elements via Accessibility"
```

---

### Task 10: SessionEventTap

**Files:**
- Create: `Sources/Clipr/AdvancedMode/SessionEventTap.swift`

Not unit-testable (needs a real tap). The protocol lets Task 12 inject a fake.

**Interfaces:**
- Consumes: `KeyInput`, `KeyModifiers`, `WindowPicker.ownerPIDOfWindow(at:)` (existing), `ClickCaptureError` (existing: `.eventTapCreationFailed`).
- Produces:
  - `enum SessionEvent: Equatable { case click(CGPoint); case ownClick; case mouseMoved(CGPoint); case key(KeyInput) }` — `ownClick` = a click on Clipr's own window (still ends a typing burst, never a step).
  - `struct SessionEventOptions: Equatable { var mouseMoves: Bool; var keys: Bool }`
  - `protocol SessionEventSource: AnyObject { var onEvent: ((SessionEvent) -> Void)? { get set }; func start(options: SessionEventOptions) throws; func stop() }`
  - `final class SessionEventTap: SessionEventSource`

- [ ] **Step 1: Implement**

```swift
// Sources/Clipr/AdvancedMode/SessionEventTap.swift
import Cocoa
import Carbon.HIToolbox

enum SessionEvent: Equatable {
    case click(CGPoint)
    /// A click on Clipr itself (menu-bar icon, control panel). Never a step, but it still ends a
    /// typing burst so text typed just before pressing Stop isn't lost.
    case ownClick
    case mouseMoved(CGPoint)
    case key(KeyInput)
}

struct SessionEventOptions: Equatable {
    var mouseMoves: Bool
    var keys: Bool
}

protocol SessionEventSource: AnyObject {
    var onEvent: ((SessionEvent) -> Void)? { get set }
    func start(options: SessionEventOptions) throws
    func stop()
}

/// One listen-only tap for everything a session observes. The mask only includes what enabled
/// features need — mouse-moved events in particular arrive at display refresh rate, and keyboard
/// events need Input Monitoring. The callback only decodes and forwards: any real work on the
/// main thread here risks the system disabling the tap for being slow.
final class SessionEventTap: SessionEventSource {
    var onEvent: ((SessionEvent) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start(options: SessionEventOptions) throws {
        var mask: CGEventMask = 1 << CGEventType.leftMouseDown.rawValue
        if options.mouseMoves {
            mask |= 1 << CGEventType.mouseMoved.rawValue | 1 << CGEventType.leftMouseDragged.rawValue
        }
        if options.keys { mask |= 1 << CGEventType.keyDown.rawValue }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                Unmanaged<SessionEventTap>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { throw ClickCaptureError.eventTapCreationFailed }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
    }

    deinit { stop() }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Re-arm rather than silently recording nothing for the rest of the session.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            NSLog("Clipr: advanced mode event tap was disabled by the system; re-enabled")
        case .leftMouseDown:
            // Resolved at click time: by the time a delayed capture runs, the menu or panel that
            // was clicked may be gone. See `WindowPicker.ownerPIDOfWindow`.
            let isOwn = WindowPicker.ownerPIDOfWindow(at: event.location) == ProcessInfo.processInfo.processIdentifier
            onEvent?(isOwn ? .ownClick : .click(event.location))
        case .mouseMoved, .leftMouseDragged:
            onEvent?(.mouseMoved(event.location))
        case .keyDown:
            guard let ns = NSEvent(cgEvent: event) else { return }
            onEvent?(.key(KeyInput(
                characters: ns.characters ?? "",
                baseCharacters: ns.charactersIgnoringModifiers ?? "",
                keyCode: ns.keyCode,
                modifiers: Self.modifiers(ns.modifierFlags),
                isSecure: IsSecureEventInputEnabled()
            )))
        default:
            break
        }
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var m: KeyModifiers = []
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.command) { m.insert(.command) }
        return m
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete. (`ClickCaptureManager` still has its own tap until Task 12; both compile side by side.)

- [ ] **Step 3: Commit**

```bash
git add Sources/Clipr/AdvancedMode/SessionEventTap.swift
git commit -m "feat: add session event tap for clicks, moves and keys"
```

---

### Task 11: StepImageSource (per-scope capture)

**Files:**
- Create: `Sources/Clipr/AdvancedMode/StepImageSource.swift`
- Modify: `Sources/Clipr/Capture/CaptureManager.swift` (drop `private` from `snapshotScreens` and `captureFullScreen`)

Not unit-testable (ScreenCaptureKit). The protocol lets Task 12 inject a fake.

**Interfaces:**
- Consumes: `CaptureManager.captureWindow(_:showsCursor:)`, `CaptureManager.captureFullScreen(_:showsCursor:)`, `WindowPicker`, `CaptureGeometry.cropped`, `StepGeometry.globalTopLeftFrame`.
- Produces:
  - `enum CaptureTarget: Equatable { case frontmostWindow; case screenContaining(CGPoint); case area(CGRect) }` (all Quartz global)
  - `struct CapturedFrame { let image: NSImage; let origin: CGPoint; let appName: String? }` — `origin` = Quartz global position of the image's top-left.
  - `protocol StepImageSource: AnyObject { var ownWindowIDs: Set<CGWindowID> { get set }; func capture(_ target: CaptureTarget, showsCursor: Bool) async throws -> CapturedFrame? }` (`nil` = nothing capturable, e.g. Clipr or Desktop frontmost)
  - `final class LiveStepImageSource: StepImageSource`

- [ ] **Step 1: Make the CaptureManager helpers internal**

In `CaptureManager.swift` change `private static func snapshotScreens` → `static func snapshotScreens` and `private static func captureFullScreen` → `static func captureFullScreen`. No other edits.

- [ ] **Step 2: Implement**

```swift
// Sources/Clipr/AdvancedMode/StepImageSource.swift
import Cocoa

enum CaptureTarget: Equatable {
    case frontmostWindow
    case screenContaining(CGPoint)
    case area(CGRect)
}

struct CapturedFrame {
    let image: NSImage
    /// Quartz global position of the image's top-left corner — what `StepGeometry` subtracts.
    let origin: CGPoint
    let appName: String?
}

protocol StepImageSource: AnyObject {
    var ownWindowIDs: Set<CGWindowID> { get set }
    func capture(_ target: CaptureTarget, showsCursor: Bool) async throws -> CapturedFrame?
}

final class LiveStepImageSource: StepImageSource {
    var ownWindowIDs: Set<CGWindowID> = []

    func capture(_ target: CaptureTarget, showsCursor: Bool) async throws -> CapturedFrame? {
        let appName = await MainActor.run { NSWorkspace.shared.frontmostApplication?.localizedName }
        switch target {
        case .frontmostWindow:
            guard let window = await MainActor.run(body: { frontmostWindow() }) else { return nil }
            let image = try await CaptureManager.captureWindow(window, showsCursor: showsCursor)
            return CapturedFrame(image: image, origin: window.bounds.origin, appName: appName)
        case .screenContaining(let point):
            guard let match = await MainActor.run(body: { Self.screen(containing: point) }) else { return nil }
            let (screen, frame) = match
            let image = try await CaptureManager.captureFullScreen(screen, showsCursor: showsCursor)
            return CapturedFrame(image: image, origin: frame.origin, appName: appName)
        case .area(let area):
            let center = CGPoint(x: area.midX, y: area.midY)
            guard let match = await MainActor.run(body: { Self.screen(containing: center) }) else { return nil }
            let (screen, frame) = match
            let full = try await CaptureManager.captureFullScreen(screen, showsCursor: showsCursor)
            let local = area.offsetBy(dx: -frame.minX, dy: -frame.minY)
            guard let cropped = CaptureGeometry.cropped(full, to: local) else { return nil }
            return CapturedFrame(image: cropped.image, origin: CGPoint(x: frame.minX + cropped.rect.minX, y: frame.minY + cropped.rect.minY), appName: appName)
        }
    }

    /// Same rules Advanced Mode has always used: never Clipr itself, never a window Clipr owns.
    @MainActor
    private func frontmostWindow() -> WindowInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        guard let window = WindowPicker.frontmostWindow(ownedBy: app.processIdentifier, in: WindowPicker.onScreenWindows()),
              !ownWindowIDs.contains(window.windowID) else { return nil }
        return window
    }

    @MainActor
    static func screen(containing point: CGPoint) -> (NSScreen, CGRect)? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        for screen in NSScreen.screens {
            let frame = StepGeometry.globalTopLeftFrame(ofScreenFrame: screen.frame, primaryScreenHeight: primaryHeight)
            if frame.contains(point) { return (screen, frame) }
        }
        return nil
    }
}
```

- [ ] **Step 3: Build and run full tests**

Run: `swift build && swift test`
Expected: Build complete; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/Clipr/AdvancedMode/StepImageSource.swift Sources/Clipr/Capture/CaptureManager.swift
git commit -m "feat: add per-scope step image capture"
```

---

### Task 12: Session coordinator rewrite and app wiring

**Files:**
- Rewrite: `Sources/Clipr/AdvancedMode/ClickCaptureManager.swift`
- Test: `Tests/ClipprTests/ClickCaptureManagerTests.swift`

**Interfaces:**
- Consumes: everything from Tasks 1–11 (and the existing coordinator/app files listed under "Further files"); `StorageManager.createSessionFolder(date:)`, `.saveStep(_:index:in:)`, `.saveAnnotations(_:rawURL:)`, `.saveStepZoom(_:stepURL:)`; `PermissionsManager.hasAccessibilityPermission()`/`requestAccessibilityPermission()`; `ClickCaptureError.accessibilityNotGranted`.
- Produces:
  - `init(storage: StorageManager, imageSource: StepImageSource = LiveStepImageSource(), describer: ClickDescribing = ClickDescriber(), eventSource: SessionEventSource = SessionEventTap(), accessibilityGranted: @escaping () -> Bool = PermissionsManager.hasAccessibilityPermission, inputMonitoringGranted: @escaping () -> Bool = { CGPreflightListenEventAccess() })`
  - `var isActive: Bool`, `var isPaused: Bool`, `var captureCursor: Bool`, `var currentSessionFolder: URL?`, `var ownWindowIDs: Set<CGWindowID>` (forwards to `imageSource`), `var onStepCaptured: ((Int) -> Void)?`, `private(set) var typingUnavailable: Bool`
  - `func start(settings: AdvancedModeSettings, area: CGRect?) throws -> URL`
  - `func captureManualStep()`
  - `func stop(completion: @escaping (SessionManifest?, URL?) -> Void)` — completion on main after all in-flight steps are written; `(manifest, folder)`, manifest `nil` if not active.
  - `func handle(_ event: SessionEvent)` (internal; tests drive it directly)

- [ ] **Step 1: Write the failing tests**

```swift
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
    var source: FakeSource!
    var images: FakeImages!
    var describer: FakeDescriber!
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ClickCaptureManagerTests`
Expected: compile failure (no `init(storage:imageSource:...)`, no `handle(_:)`).

- [ ] **Step 3: Implement**

Replace the whole of `ClickCaptureManager.swift`:

```swift
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
    private var inFlight: [UUID: Task<Void, Never>] = [:]

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
    func stop(completion: @escaping (SessionManifest?, URL?) -> Void) {
        guard let folder = sessionFolder else { return completion(nil, nil) }
        eventSource.stop()
        if let pending { pending.work.cancel(); fire(pending) }
        pending = nil
        endTypingBurst()
        idleWork?.cancel()
        let tasks = Array(inFlight.values)
        Task { @MainActor in
            for task in tasks { await task.value }
            let final = self.manifest
            self.sessionFolder = nil
            self.manifest = nil
            self.isPaused = false
            completion(final, folder)
        }
    }

    func captureManualStep() {
        guard isActive, !isPaused else { return }
        _ = trail.drain()
        enqueue(kind: .manual, target: scopeTarget(for: nil), click: nil, trail: [], caption: { _ in nil })
    }

    // MARK: Events

    func handle(_ event: SessionEvent) {
        guard isActive, !isPaused else { return }
        switch event {
        case .mouseMoved(let p):
            if settings.cursorTrail { trail.add(p) }
        case .ownClick:
            endTypingBurst()
        case .click(let p):
            endTypingBurst()
            var points = trail.drain()
            if let previous = pending {
                // A second click inside the delay replaces the first (double-click, fast
                // clicking); its trail is kept so the path still starts where the user began.
                previous.work.cancel()
                previous.describe?.cancel()
                points = previous.trail + points
            }
            let describe = settings.autoCaptions ? Task { await self.describer.describe(at: p) } : nil
            let work = DispatchWorkItem { [weak self] in
                guard let self, let pending = self.pending else { return }
                self.pending = nil
                self.fire(pending)
            }
            pending = PendingClick(point: p, trail: points, describe: describe, work: work)
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
        enqueue(kind: .click, target: scopeTarget(for: click.point), click: click.point, trail: click.trail, caption: caption)
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

    private func enqueue(
        kind: StepRecord.Kind, target: CaptureTarget, click: CGPoint?, trail: [CGPoint],
        skipIf: @escaping () async -> Bool = { false }, caption: @escaping (_ appName: String?) async -> String?
    ) {
        guard let folder = sessionFolder else { return }
        let id = UUID()
        let settings = self.settings
        let showsCursor = captureCursor
        let task = Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.inFlight[id] = nil } }
            if await skipIf() { return }
            let frame: CapturedFrame?
            do {
                frame = try await self.imageSource.capture(target, showsCursor: showsCursor)
            } catch {
                NSLog("Clipr: advanced mode step capture failed: \(error)")
                return
            }
            guard let frame else { return }
            let text = await caption(frame.appName)
            await MainActor.run {
                self.write(frame, kind: kind, click: click, trail: trail, caption: text, settings: settings, folder: folder)
            }
        }
        inFlight[id] = task
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
    /// the generic caption instead of holding the step back.
    private static func value<T>(of task: Task<T?, Never>?, timeout: TimeInterval) async -> T?? {
        guard let task else { return nil }
        return await withTaskGroup(of: T??.self) { group in
            group.addTask { .some(await task.value) }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
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
```

Note on the typing-field check in `testSecureTypingWritesNoStep`: the fake reports the focused field as secure even though the key wasn't flagged secure, which exercises the `skipIf` defence.

The manager's API change breaks `AdvancedModeCoordinator` and `AppDelegate`, and `swift test` can't run until the whole target compiles, so the remaining steps of this task update those callers before anything is run.

**Further files in this task:**
- Modify: `Sources/Clipr/AdvancedMode/AdvancedModeCoordinator.swift`
- Create: `Sources/Clipr/AdvancedMode/AreaPicker.swift`
- Modify: `Sources/Clipr/AdvancedMode/ReviewWindowController.swift`, `Sources/Clipr/AdvancedMode/ReviewView.swift`
- Modify: `Sources/Clipr/AdvancedMode/AdvancedModeControlPanel.swift`
- Modify: `Sources/Clipr/AppDelegate.swift`

**Further interfaces:**
- Consumes: the `ClickCaptureManager` API above; `SessionManifestStore.load(from:)`; `CaptureManager.snapshotScreens`; `CaptureOverlayWindow.showAll/restoreHiddenWindows`; `StepGeometry.globalTopLeftRect`.
- Produces:
  - `AdvancedModeCoordinator`: `enum StartOutcome { case started, accessibilityNotGranted, startFailed(Error) }`; `var isActive: Bool`; `var typingUnavailable: Bool`; `func start(settings: AdvancedModeSettings, area: CGRect?, ownWindowIDs: Set<CGWindowID>) -> StartOutcome`; `func stop(completion: @escaping (ReviewWindowController?) -> Void)`; `func captureManualStep()`; existing `togglePause()`, `isPaused`, `reviewLastSession()`, `reviewWindows`, `captureCursor`, `onStepCaptured`.
  - `enum AreaPicker { static func pick(showsCursor: Bool, completion: @escaping (CGRect?) -> Void) }`
  - `ReviewWindowController.init(manifest: SessionManifest, sessionFolder: URL, storage: StorageManager)`
  - `AdvancedModeControlState.warning: String?`

- [ ] **Step 4: Coordinator**

Replace `toggle(ownWindowIDs:)`, `stepURLs(in:)`, and `openReview(stepURLs:sessionFolder:)` with:

```swift
    enum StartOutcome {
        case started
        case accessibilityNotGranted
        case startFailed(Error)
    }

    var isActive: Bool { clickCaptureManager.isActive }
    var typingUnavailable: Bool { clickCaptureManager.typingUnavailable }

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
```

In `reviewLastSession()`, replace the loop body with:

```swift
        for folder in sessions {
            let manifest = SessionManifestStore.load(from: folder)
            if !manifest.steps.isEmpty { return openReview(manifest: manifest, sessionFolder: folder) }
        }
        return nil
```

And `openReview`:

```swift
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
```

Also delete the `ToggleOutcome` enum.

- [ ] **Step 5: Area picker**

```swift
// Sources/Clipr/AdvancedMode/AreaPicker.swift
import Cocoa

/// The one-time area selection for Fixed area scope, reusing the normal capture overlay.
/// Choosing a whole screen or a window in the overlay sets the area to that screen or window.
enum AreaPicker {
    static func pick(showsCursor: Bool, completion: @escaping (CGRect?) -> Void) {
        Task { @MainActor in
            let frozen: [CGDirectDisplayID: NSImage]
            do {
                frozen = try await CaptureManager.snapshotScreens(NSScreen.screens, showsCursor: showsCursor)
            } catch {
                NSLog("Clipr: area selection failed: \(error)")
                return completion(nil)
            }
            CaptureOverlayWindow.showAll(frozenScreens: frozen) { result in
                CaptureOverlayWindow.restoreHiddenWindows()
                let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                switch result {
                case .area(let rect, let screen):
                    completion(StepGeometry.globalTopLeftRect(viewLocal: rect, screenFrame: screen.frame, primaryScreenHeight: primaryHeight))
                case .fullScreen(let screen):
                    completion(StepGeometry.globalTopLeftFrame(ofScreenFrame: screen.frame, primaryScreenHeight: primaryHeight))
                case .window(let info):
                    completion(info.bounds)
                case .cancelled:
                    completion(nil)
                }
            }
        }
    }
}
```

- [ ] **Step 6: Review shows captions**

`ReviewWindowController.init` becomes `init(manifest: SessionManifest, sessionFolder: URL, storage: StorageManager)`; title `"Review — \(sessionFolder.lastPathComponent)"`; build the view with:

```swift
        window.contentView = NSHostingView(rootView: ReviewView(
            steps: manifest.steps.map { ReviewView.Step(url: sessionFolder.appendingPathComponent($0.file), caption: $0.caption) },
            onOpenEditor: { [weak self] url in self?.openEditor(for: url) },
            onDelete: { url in try? FileManager.default.removeItem(at: url) },
            onShowInFinder: { NSWorkspace.shared.activateFileViewerSelecting([sessionFolder]) }
        ))
```

In `ReviewView`: add `struct Step: Hashable { let url: URL; let caption: String? }`; replace `@State var stepURLs: [URL]` with `@State var steps: [Step]`; `onShowInFinder` becomes non-optional `() -> Void` (always shown); header count uses `steps.count`; `ForEach(steps, id: \.self) { step in ... }` using `step.url`; under the filename `Text`, add:

```swift
                        if let caption = step.caption {
                            // Read-only here; editing captions is the Review sub-project.
                            Text(caption.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "\\", with: ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
```

Delete removes with `steps.removeAll { $0.url == step.url }`.

- [ ] **Step 7: Control panel warning row**

In `AdvancedModeControlState` add `@Published var warning: String?`. Wrap `AdvancedModeControlView.body`'s `HStack` in a `VStack(spacing: 4)`; below it:

```swift
            if let warning = state.warning {
                Text(warning)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
```

Move `.padding`, `.background(.regularMaterial, in: Capsule())`, `.overlay` and `.fixedSize()` to the `VStack`, and change both `Capsule()` uses to `RoundedRectangle(cornerRadius: 18)` so a two-line panel isn't pill-clipped. After building the hosting view in `AdvancedModeControlPanel.init`, nothing else changes; the panel resizes itself in Step 8.

- [ ] **Step 8: AppDelegate wiring**

Add `case advancedModeStep = 3` to `HotkeyID`. Replace `toggleAdvancedMode()`:

```swift
    private func toggleAdvancedMode() {
        if advancedMode.isActive {
            unregisterStepHotkey()
            advancedMode.stop { [weak self] review in
                guard let self else { return }
                self.statusItemController.setAdvancedModeActive(false)
                self.hideAdvancedModePanel()
                if let review {
                    review.present()
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    showNoStepsCapturedAlert()
                }
            }
            return
        }
        let advancedSettings = settings.advancedMode
        guard advancedSettings.scope == .fixedArea else {
            return startAdvancedMode(advancedSettings, area: nil)
        }
        AreaPicker.pick(showsCursor: settings.captureCursor) { [weak self] area in
            // Cancelling the selection simply doesn't start the session — no alert.
            guard let self, let area else { return }
            self.startAdvancedMode(advancedSettings, area: area)
        }
    }

    private func startAdvancedMode(_ advancedSettings: AdvancedModeSettings, area: CGRect?) {
        switch advancedMode.start(settings: advancedSettings, area: area, ownWindowIDs: currentOwnWindowIDs()) {
        case .started:
            statusItemController.setAdvancedModeActive(true)
            showAdvancedModePanel()
            if advancedMode.typingUnavailable {
                advancedModePanel?.state.warning = "Typing not recorded — grant Input Monitoring"
                advancedModePanel?.setContentSize(advancedModePanel?.contentView?.fittingSize ?? .zero)
            }
            registerStepHotkey(advancedSettings.stepHotkey)
        case .accessibilityNotGranted:
            showPermissionAlert(pane: .accessibility, message: "Clipr needs Accessibility access to detect clicks for Advanced Mode.")
        case .startFailed(let error):
            NSLog("Clipr: failed to start advanced mode: \(error)")
            let alert = NSAlert()
            alert.messageText = "Couldn't start Advanced Mode"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    /// Only while a session runs, so the combination stays free for other apps the rest of the time.
    private func registerStepHotkey(_ binding: HotkeyBinding?) {
        guard let binding else { return }
        if !hotkeyManager.register(binding, id: HotkeyID.advancedModeStep.rawValue, handler: { [weak self] in
            self?.advancedMode.captureManualStep()
        }) {
            NSLog("Clipr: step hotkey \(binding.displayString) unavailable for this session")
        }
    }

    private func unregisterStepHotkey() {
        hotkeyManager.unregister(id: HotkeyID.advancedModeStep.rawValue)
    }
```

Keep `showAdvancedModePanel`, `hideAdvancedModePanel`, `toggleAdvancedModePause`, `reviewLastSession` as they are.

- [ ] **Step 9: Build and run all tests**

Run: `swift build && swift test --filter ClickCaptureManagerTests && swift test`
Expected: Build complete; 13 `ClickCaptureManagerTests` pass; full suite passes.

- [ ] **Step 10: Commit**

```bash
git add Sources/Clipr/AdvancedMode Sources/Clipr/AppDelegate.swift Tests/ClipprTests/ClickCaptureManagerTests.swift
git commit -m "feat: rewrite Advanced Mode session with manifest, markers, captions and typing"
```

---

### Task 13: Preferences section

**Files:**
- Modify: `Sources/Clipr/PreferencesUI/PreferencesView.swift`

**Interfaces:**
- Consumes: `SettingsStore.advancedMode`, `AdvancedModeSettings`, `HotkeyRecorderView(binding:)` (existing), `CGPreflightListenEventAccess()`, `CGRequestListenEventAccess()`.

- [ ] **Step 1: Implement**

Add state and initialise it in `init`:

```swift
    @State private var advanced: AdvancedModeSettings
    @State private var inputMonitoringGranted = CGPreflightListenEventAccess()
```

```swift
        _advanced = State(initialValue: settings.advancedMode)
```

Add a helper that persists on every change:

```swift
    private func advancedBinding<T>(_ keyPath: WritableKeyPath<AdvancedModeSettings, T>) -> Binding<T> {
        Binding(
            get: { advanced[keyPath: keyPath] },
            set: { advanced[keyPath: keyPath] = $0; settings.advancedMode = advanced }
        )
    }
```

Insert before the "About" `Section`:

```swift
            Section {
                HStack {
                    Toggle("Click marker", isOn: advancedBinding(\.clickMarker))
                    Spacer()
                    Picker("", selection: advancedBinding(\.markerStyle)) {
                        Text("Ring").tag(AdvancedModeSettings.MarkerStyle.ring)
                        Text("Dot").tag(AdvancedModeSettings.MarkerStyle.dot)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 110)
                    .disabled(!advanced.clickMarker)
                }
                Toggle("Auto captions", isOn: advancedBinding(\.autoCaptions))
                Toggle("Cursor trail", isOn: advancedBinding(\.cursorTrail))
                Toggle("Zoom on click", isOn: advancedBinding(\.zoomOnClick))
                HStack {
                    Toggle("Typing steps", isOn: advancedBinding(\.typingSteps))
                    Spacer()
                    if advanced.typingSteps && !inputMonitoringGranted {
                        Button("Grant…") {
                            inputMonitoringGranted = CGRequestListenEventAccess()
                        }
                        .help("Typing steps need Input Monitoring permission")
                    }
                }
                Picker("Capture", selection: advancedBinding(\.scope)) {
                    Text("Window").tag(AdvancedModeSettings.Scope.window)
                    Text("Screen").tag(AdvancedModeSettings.Scope.screen)
                    Text("Fixed area").tag(AdvancedModeSettings.Scope.fixedArea)
                }
                HStack {
                    Text("Capture delay")
                    Slider(value: advancedBinding(\.captureDelay), in: 0...2, step: 0.1)
                    Text(String(format: "%.1f s", advanced.captureDelay))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text("Step hotkey")
                    Spacer()
                    if let hotkey = advanced.stepHotkey {
                        HotkeyRecorderView(binding: Binding(
                            get: { hotkey },
                            set: { advanced.stepHotkey = $0; settings.advancedMode = advanced }
                        ))
                        Button("Clear") { advanced.stepHotkey = nil; settings.advancedMode = advanced }
                    } else {
                        Button("Set…") {
                            advanced.stepHotkey = HotkeyBinding(keyCode: 1, modifiers: HotkeyBinding.Modifier.control.rawValue | HotkeyBinding.Modifier.option.rawValue)
                            settings.advancedMode = advanced
                        }
                        .help("Adds a hotkey (⌃⌥S) you can then re-record. Active only during a session.")
                    }
                }
            } header: {
                Text("Advanced Mode")
            } footer: {
                Text("Changes apply to the next Advanced Mode session.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
```

(`keyCode: 1` is the S key on ANSI layouts, matching the help text.)

If the window is now taller than the screen on small displays, wrap the `Form` in a `ScrollView` and keep `.frame(width: 420)`.

- [ ] **Step 2: Build and run tests**

Run: `swift build && swift test`
Expected: Build complete; all tests pass.

- [ ] **Step 3: Visual check**

Run: `./Scripts/build-app.sh && open Clipr.app`, open Preferences. Expected: an "Advanced Mode" section with all controls; toggling persists across reopening Preferences; the marker picker disables when Click marker is off.

- [ ] **Step 4: Commit**

```bash
git add Sources/Clipr/PreferencesUI/PreferencesView.swift
git commit -m "feat: add Advanced Mode preferences"
```

---

### Task 14: Manual checklist and final verification

**Files:**
- Create: `docs/superpowers/checklists/advanced-mode-capture-manual.md`

- [ ] **Step 1: Write the checklist**

```markdown
# Advanced Mode Capture — Manual Checklist

Build with `./Scripts/build-app.sh`, quit any running Clipr, `open Clipr.app`. Re-grant
Accessibility / Screen Recording / Input Monitoring if prompted (ad-hoc rebuilds can drop them).

## Scopes (defaults otherwise)
- [ ] Window: click 3 buttons in Safari → 3 steps; each has a red ring on the clicked control.
- [ ] Screen: same clicks → full-display steps; rings on the right spots, including on a second display.
- [ ] Fixed area: start → overlay appears; drag an area → steps are that area only.
- [ ] Fixed area: start → press Esc in the overlay → no session, no alert.

## Features
- [ ] Captions: Review shows "Click Save in Safari"-style captions; a menu item shows "Choose File ▸ …".
- [ ] Marker style Dot: small filled dot instead of ring.
- [ ] Marker off: no annotations on new steps.
- [ ] Trail on: faint path leading to each click; editable in editor.
- [ ] Zoom on: `Step_NN_zoom.png` next to each click step, centred on the click.
- [ ] Typing on (Input Monitoring granted): type a name in a text field, click elsewhere → a "Type "…" in Name" step showing the filled field, before the click step.
- [ ] Typing on: type in a password field → no typing step; `session.json` has no trace of it.
- [ ] Typing on without Input Monitoring: panel shows the warning; clicks still record.
- [ ] Shortcut: ⌘S in an app → "Press ⌘S" step.
- [ ] Step hotkey: set one, start session, press it → manual step without caption/marker; after Stop the hotkey no longer fires.
- [ ] Delay 1.5 s: open a menu by clicking → step shows the menu open.
- [ ] Double-click → one step.

## Session
- [ ] Pause → clicks ignored; Resume → numbering continues.
- [ ] Stop right after a click (within the delay) → that click's step is in Review.
- [ ] Stop button on panel / menu-bar Stop never creates a step.
- [ ] Open a step in the editor → marker and trail are selectable, movable, deletable.
- [ ] Review Last Session after relaunching Clipr → same steps and captions.
- [ ] Old session folder (no session.json) → Review lists its steps without captions.
```

- [ ] **Step 2: Full verification**

Run: `swift build && swift test && ./Scripts/build-app.sh`
Expected: Build complete; all tests pass; "Built Clipr.app".

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/checklists/advanced-mode-capture-manual.md
git commit -m "docs: manual checklist for Advanced Mode capture"
```

- [ ] **Step 4: Run the manual checklist** with the user (they hold the permissions), record any failures as follow-up tasks.
