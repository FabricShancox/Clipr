# Advanced Mode Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export a reviewed Advanced Mode session from the Review window as a PDF, a self-contained HTML file, a Markdown folder, an animated GIF, or rich text on the clipboard.

**Architecture:** A pure `GuideDocument` (built from the manifest, the Review selection and `ExportOptions`) feeds format writers: `HTMLGuideWriter` (one template behind HTML, PDF and the clipboard), `MarkdownGuideWriter` and `GIFGuideExporter`. `GuideImages` renders each step's raw PNG with its annotations flattened, downsampled and encoded; `PDFGuideExporter` prints the HTML through an offscreen `WKWebView`; `GuideClipboard` writes HTML + RTF. `GuideExporter` runs an export off the main thread with progress and cancellation, assembling output in a work folder and moving it into place only on success. `ExportSheetModel`/`ExportSheet`/`ExportFlowController` give Review an Export… button and ⇧⌘E.

**Tech Stack:** Swift 5.10 (tools) / Swift 6.2 compiler in Swift 5 mode, SwiftPM, SwiftUI + AppKit, WebKit (`WKWebView.printOperation(with:)`), ImageIO (GIF/PNG/JPEG), PDFKit (tests only), XCTest. macOS 14.

**Spec:** `docs/superpowers/specs/2026-10-04-advanced-mode-export-design.md`

## Global Constraints

- Platform floor macOS 14 (`Package.swift`). No new package dependencies; system frameworks only (WebKit, ImageIO, PDFKit, UniformTypeIdentifiers).
- Build `swift build`; tests `swift test` from the repo root; app bundle `./Scripts/build-app.sh` (never commit `Clipr.app`). macOS has no `timeout` binary — tests that wait use XCTest expectations with their own timeouts.
- Every commit message ends with a blank line then `Claude-Session: https://claude.ai/code/session_01J9DeGERVvr6uhbMe87JjkA`.
- Formats exactly: PDF (one paginated file), HTML (one self-contained `.html`, images as data URIs), Markdown (folder: `guide.md` + `images/`, relative links), GIF (animated slideshow, caption band per frame), Copy as Rich Text (HTML + RTF on the clipboard).
- One HTML template drives HTML, PDF and the clipboard. Light theme only, system font stack.
- Steps exported: the selection if any, otherwise all, in Review order, renumbered 1…N.
- Images are the step's raw PNG with its annotation sidecar flattened on.
- `imageSize` S/M/L/Full (nil = Full) → 40% / 60% / 80% / 100% of the content width.
- Image pixels: Full 1600px wide, others proportional; PNG, or JPEG q0.85 when the PNG would exceed 1.5 MB.
- Header: title (h1), then "4 Oct 2026 · 7 steps" in secondary grey. No caption → "Step N". Missing image → light grey box "Image unavailable". Zoom inset beside the image at ~30% width.
- PDF: A4 or US Letter by locale, 18mm margins, a step never splits across pages, 30 s timeout; failure → alert suggesting HTML export.
- Markdown: `![Step N](images/step-NN.png)` for Full, `<img src="images/step-NN.png" alt="Step N" width="60%">` for sized steps, close-ups as `![Step 1 close-up](images/step-01-zoom.png)`. Existing `guide.md` → ask Replace or Cancel.
- GIF: canvas ≤ 1000px wide, frame time 1–5 s (default 2), loops forever, caption plain text with "Step N" fallback.
- `ExportOptions`: `format`, `title` (default: session folder name), `includeZoom` (default off), `gifFrameSeconds` (default 2). Last format / includeZoom / gifFrameSeconds remembered via `SettingsStore`.
- Copy note text exactly: "Images may not paste into some web apps — use PDF or Markdown".
- Export lives in Review: **Export…** button and ⇧⌘E (a hidden keyboard-shortcut button in `ReviewView`, as for Review's other shortcuts — the main menu has no such items). Read-only sessions can export.
- Code comments explain *why*, in full sentences, matching repo style.

## Rulings on spec ambiguities (recorded so executors don't "fix" them)

- **`GuideFormat`, not `ExportFormat`:** `Sources/Clipr/Storage/ExportFormat.swift` already names the editor's PNG/JPEG choice.
- **`RenderedImages { steps, zooms }`** replaces the spec's `images: [Int: GuideImage]`: a step can have both an image and a close-up.
- **`GuideImages.render` returns `GuideImageRender { image, sidecarDamaged }`** so the damaged-sidecar warning reaches the exporter.
- **JPEG-fallback images are named `.jpg`** (`images/step-NN.jpg`), not `.png`.
- **Markdown omits the app name** (the spec's Markdown layout shows none); HTML/PDF/clipboard show it.
- **Date line is always English `d MMM yyyy`** ("4 Oct 2026"), matching the spec example and Clipr's English-only copy.
- **Markdown escaping also escapes `*`** (beyond the spec's list), and **line breaks in captions become spaces** in every format, so a caption can never end a Markdown heading early.
- **A selection naming no step still in the manifest exports all steps**, rather than an empty guide.
- **GIF ignores per-step size and close-ups** (the include close-ups toggle is hidden for GIF); canvas width is the widest image clamped to 480…1000px; images are never enlarged.
- **A close-up whose file is missing is silently left out** (no warning); close-ups render at 480px (30% of 1600).
- **"Toolbar button"** = a button in Review's header bar (Review has no `NSToolbar`).
- **Markdown Replace** moves `images/` before `guide.md` and replaces the whole `images/` folder.
- **PDF printing** runs `NSPrintOperation.runModal(for:…)` against a borderless window that is never shown — a `WKWebView` print operation needs a window and a framed view or it prints blank pages. Verified with a prototype before this plan was written (30 steps → 15 pages, every heading extractable).
- **Clipboard success** shows no extra UI beyond the progress sheet closing.

## Review Focus

1. **Captions built from hostile Accessibility labels** (`[x](javascript:…)`, `<img onerror=…>`, `<script>`, a hostile app name or title) — the exported HTML/PDF/clipboard keeps the words but contains no active markup. Pinned in Task 3 (`testHostileCaptionsProduceNoActiveContent`).
2. **A caption containing a line break** (multi-line text pasted into a caption) — the Markdown heading stays on one line and the image link stays below it instead of being swallowed or turned into a new heading. Pinned in Task 4 (`testMultiLineCaptionStaysInHeading`).
3. **Retina captures (2 pixels per point)** — the size cap applies to pixels, and every pixel is kept when under the cap, so exports are sharp but not oversized. Pinned in Task 5 (`testRetinaImageCapsPixelsNotPoints`).
4. **A Review selection that no longer names any step** (steps selected, then deleted) — export falls back to all steps rather than producing an empty guide. Pinned in Task 1 (`testStaleSelectionFallsBackToAllSteps`).
5. **Exporting over an existing file or Markdown folder the user agreed to replace** — the old output is replaced by the complete new one, with no stale images and no leftover work files. Pinned in Task 9 (`testReplacesExistingFileAtDestination`, `testMarkdownReplacesGuideAndImagesInChosenFolder`).

---

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `Sources/Clipr/AdvancedMode/Export/GuideDocument.swift` | Create | `GuideFormat`, `ExportOptions`, `GuideImageRef`, `GuideImage`, `RenderedImages`, `GuideStep`, `GuideDocument.make`, `ImageSize.widthPercent` |
| `Sources/Clipr/AdvancedMode/Export/CaptionMarkup.swift` | Create | Untrusted inline Markdown → safe HTML / Markdown / plain text |
| `Sources/Clipr/AdvancedMode/Export/HTMLGuideWriter.swift` | Create | The guide HTML template (embedded or linked images) |
| `Sources/Clipr/AdvancedMode/Export/MarkdownGuideWriter.swift` | Create | `guide.md` text and the `guide.md` + `images/` folder |
| `Sources/Clipr/AdvancedMode/Export/GuideImages.swift` | Create | Load PNG, flatten annotations, downsample, encode PNG/JPEG |
| `Sources/Clipr/AdvancedMode/Export/GIFGuideExporter.swift` | Create | Animated GIF on a fixed canvas with caption bands |
| `Sources/Clipr/AdvancedMode/Export/PDFGuideExporter.swift` | Create | Offscreen `WKWebView` print-to-PDF with timeout |
| `Sources/Clipr/AdvancedMode/Export/GuideClipboard.swift` | Create | HTML + RTF on a pasteboard; spike-driven web-app note |
| `Sources/Clipr/AdvancedMode/Export/GuideExporter.swift` | Create | Coordinator: render off-main, progress, cancel, work folder → move into place, warnings, errors |
| `Sources/Clipr/AdvancedMode/Export/ExportSheetModel.swift` | Create | Sheet state from the session + remembered options |
| `Sources/Clipr/AdvancedMode/Export/ExportSheet.swift` | Create | SwiftUI options sheet and progress sheet |
| `Sources/Clipr/AdvancedMode/Export/ExportFlowController.swift` | Create | Sheet → panel → Replace check → progress → reveal/alert |
| `Sources/Clipr/Settings/SettingsStore.swift` | Modify | `exportOptions(title:)`, `rememberExportOptions(_:)` |
| `Sources/Clipr/AdvancedMode/ReviewView.swift` | Modify | `onExport`, Export… button, ⇧⌘E hidden button |
| `Sources/Clipr/AdvancedMode/ReviewWindowController.swift` | Modify | `settings` init parameter, owns `ExportFlowController` |
| `docs/superpowers/checklists/advanced-mode-capture-manual.md` | Modify | Clipboard spike record (Task 1) and Export checklist (Task 11) |
| `Tests/ClipprTests/GuideDocumentTests.swift`, `CaptionMarkupTests.swift`, `HTMLGuideWriterTests.swift`, `MarkdownGuideWriterTests.swift`, `GuideImagesTests.swift`, `GIFGuideExporterTests.swift`, `PDFGuideExporterTests.swift`, `GuideClipboardTests.swift`, `GuideExporterTests.swift`, `ExportSheetModelTests.swift` | Create | Unit / integration tests |
| `Tests/ClipprTests/SettingsStoreTests.swift` | Modify | Export options persistence tests |

SwiftPM picks up `Sources/Clipr/AdvancedMode/Export/` automatically; no `Package.swift` change.

Test filters below use `ClipprTests.<Suite>` so that, e.g., `GuideExporterTests` doesn't also match `GIFGuideExporterTests`.

---

### Task 1: GuideDocument, export options, and the clipboard spike

**Files:**
- Create: `Sources/Clipr/AdvancedMode/Export/GuideDocument.swift`
- Test: `Tests/ClipprTests/GuideDocumentTests.swift`
- Modify: `docs/superpowers/checklists/advanced-mode-capture-manual.md` (append spike record)

**Interfaces:**
- Consumes: `SessionManifest`, `StepRecord` (`file`, `caption`, `appName`, `zoomFile`, `imageSize: ImageSize?`, `id`), `ImageSize.widthFraction` (`AdvancedMode/SessionManifest.swift`); `FilenameGenerator.sanitizedBaseName(_:) -> String?`.
- Produces:
  - `enum GuideFormat: String, CaseIterable, Identifiable { case pdf, html, markdown, gif, clipboard }` with `var title: String`, `var fileExtension: String?`, `func suggestedFileName(for title: String) -> String`
  - `struct ExportOptions: Equatable { static let gifFrameRange: ClosedRange<Double>; var format: GuideFormat = .pdf; var title: String; var includeZoom = false; var gifFrameSeconds: Double = 2 }` (memberwise `ExportOptions(format:title:includeZoom:gifFrameSeconds:)`)
  - `extension ImageSize { var widthPercent: Int }` (40/60/80/100)
  - `enum GuideImageRef: Equatable { case file(URL), missing }`
  - `struct GuideImage: Equatable { enum Kind { case png, jpeg }; let data: Data; let pixelWidth: Int; let pixelHeight: Int; let kind: Kind; var mimeType: String; static func fileName(step: Int, zoom: Bool, kind: Kind) -> String }`
  - `struct RenderedImages: Equatable { var steps: [Int: GuideImage] = [:]; var zooms: [Int: GuideImage] = [:] }`
  - `struct GuideStep: Equatable { let number: Int; let caption: String?; let appName: String?; let imageSize: ImageSize; let image: GuideImageRef; let zoom: GuideImageRef? }`
  - `struct GuideDocument: Equatable { let title: String; let date: Date; let steps: [GuideStep]; static func make(manifest: SessionManifest, folder: URL, selection: Set<UUID>, options: ExportOptions) -> GuideDocument; var subtitle: String; static func dateText(_ date: Date, timeZone: TimeZone = .current) -> String }`

- [ ] **Step 1: Clipboard spike (manual — outcome decides Task 8's `GuideClipboard.imagesMayBeDropped`)**

Write this throwaway script outside the repo (it is never committed):

```bash
cat > "$TMPDIR/clipr-clipboard-spike.swift" <<'EOF'
// Clipboard spike for Advanced Mode export: puts a one-step guide (heading, bold text, one
// data-URI image) on the general pasteboard as HTML + RTF, the same two flavours GuideClipboard
// will write. Not part of the app.
import AppKit

let side = 120
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.systemRed.setFill()
NSRect(x: 0, y: 0, width: side, height: side).fill()
NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!

let html = """
<!doctype html><html><head><meta charset="utf-8"></head><body>
<h1>Clipr clipboard spike</h1>
<h2>1. Click <strong>Save</strong> in Safari</h2>
<img src="data:image/png;base64,\(png.base64EncodedString())" alt="Step 1" style="width:120px">
</body></html>
"""
let attributed = NSAttributedString(html: Data(html.utf8), options: [.characterEncoding: String.Encoding.utf8.rawValue],
                                    documentAttributes: nil)!
let rtf = attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])!
let pasteboard = NSPasteboard.general
pasteboard.clearContents()
pasteboard.setString(html, forType: .html)
pasteboard.setData(rtf, forType: .rtf)
print("Copied spike guide: HTML \(html.utf8.count) bytes, RTF \(rtf.count) bytes")
EOF
swift "$TMPDIR/clipr-clipboard-spike.swift"
```

Expected: `Copied spike guide: HTML … bytes, RTF … bytes`.

Then, without copying anything else, paste (⌘V) into each target, re-running the script before each paste: a new TextEdit rich-text document (control), a new Google Docs document in Safari, a new Notion page, and a new Confluence page in the editor. For each, note whether the heading with **Save** in bold survived and whether the red square image survived. This needs a human (or an agent driving the browser with a signed-in session); if a target is unavailable, record "Not tested — no access".

Append to `docs/superpowers/checklists/advanced-mode-capture-manual.md`, filling every result cell with exactly one of `Kept`, `Dropped`, `Not tested — no access`, and the run line with the real date and `sw_vers -productVersion` output:

```markdown

## Export — clipboard spike

Run on (date, macOS version): 
Script: `$TMPDIR/clipr-clipboard-spike.swift` (heading, bold text, one data-URI PNG as HTML + RTF).

| Target | Heading + bold | Image |
|---|---|---|
| TextEdit (control) | | |
| Google Docs (Safari) | | |
| Notion (web) | | |
| Confluence (web) | | |

Decision: `GuideClipboard.imagesMayBeDropped` is `false` only if every web target's Image cell is `Kept`; otherwise `true` and the export sheet shows the Copy note.
```

Then write the decision line's outcome (`true` or `false`) on a new line under it: `Outcome: imagesMayBeDropped = true` (or `false`).

- [ ] **Step 2: Write the failing test**

Create `Tests/ClipprTests/GuideDocumentTests.swift`:

```swift
// Tests/ClipprTests/GuideDocumentTests.swift
import XCTest
@testable import Clipr

final class GuideDocumentTests: XCTestCase {
    var folder: URL!
    var manifest: SessionManifest!
    let created = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Session_2026-10-04_09-30-00")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["Step_01.png", "Step_02.png", "Step_02_zoom.png"] {
            FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data([1]))
        }
        // Step_03.png is deliberately not created: that step's image is missing.
        manifest = SessionManifest(createdAt: created, steps: [
            step("Step_01.png", caption: "Click **Save**", app: "Safari", size: nil),
            step("Step_02.png", caption: "   ", app: " ", size: .small, zoom: "Step_02_zoom.png"),
            step("Step_03.png", caption: nil, app: nil, size: .large, zoom: "Step_03_zoom.png"),
        ])
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    private func step(_ file: String, caption: String?, app: String?, size: ImageSize?, zoom: String? = nil) -> StepRecord {
        StepRecord(id: UUID(), file: file, kind: .click, caption: caption, clickPoint: nil,
                   zoomFile: zoom, appName: app, capturedAt: created, imageSize: size)
    }

    private func make(selection: Set<UUID> = [], includeZoom: Bool = false, title: String = "Guide") -> GuideDocument {
        GuideDocument.make(manifest: manifest, folder: folder, selection: selection,
                           options: ExportOptions(title: title, includeZoom: includeZoom))
    }

    func testAllStepsWhenNothingSelected() {
        let doc = make()
        XCTAssertEqual(doc.steps.map(\.number), [1, 2, 3])
        XCTAssertEqual(doc.steps.map(\.caption), ["Click **Save**", nil, nil])
        XCTAssertEqual(doc.steps.map(\.appName), ["Safari", nil, nil])
        XCTAssertEqual(doc.date, created)
    }

    func testSelectionKeepsReviewOrderAndRenumbers() {
        let ids = manifest.steps.map(\.id)
        let doc = make(selection: [ids[2], ids[0]])
        XCTAssertEqual(doc.steps.map(\.number), [1, 2])
        XCTAssertEqual(doc.steps.map(\.caption), ["Click **Save**", nil])
        XCTAssertEqual(doc.steps[1].image, .missing)
    }

    func testStaleSelectionFallsBackToAllSteps() {
        let doc = make(selection: [UUID()])
        XCTAssertEqual(doc.steps.count, 3)
    }

    func testSizesWithNilMeaningFull() {
        XCTAssertEqual(make().steps.map(\.imageSize), [.full, .small, .large])
        XCTAssertEqual(ImageSize.allCases.map(\.widthPercent), [40, 60, 80, 100])
    }

    func testZoomOnlyWhenIncludedAndOnDisk() {
        XCTAssertEqual(make().steps.map(\.zoom), [nil, nil, nil])
        let zoomed = make(includeZoom: true)
        XCTAssertEqual(zoomed.steps[0].zoom, nil)
        XCTAssertEqual(zoomed.steps[1].zoom, .file(folder.appendingPathComponent("Step_02_zoom.png")))
        XCTAssertEqual(zoomed.steps[2].zoom, nil, "a close-up whose file is gone is left out")
    }

    func testMissingImageBecomesMissingRef() {
        let doc = make()
        XCTAssertEqual(doc.steps[0].image, .file(folder.appendingPathComponent("Step_01.png")))
        XCTAssertEqual(doc.steps[2].image, .missing)
    }

    func testTitleIsTrimmedAndDefaultsToFolderName() {
        XCTAssertEqual(make(title: "  Set up VPN \n now ").title, "Set up VPN   now")
        XCTAssertEqual(make(title: "   ").title, "Session_2026-10-04_09-30-00")
    }

    func testSubtitle() {
        XCTAssertEqual(GuideDocument.dateText(created, timeZone: TimeZone(identifier: "UTC")!), "4 Oct 2026")
        XCTAssertEqual(make().subtitle, "4 Oct 2026 · 3 steps")
        XCTAssertEqual(make(selection: [manifest.steps[0].id]).subtitle, "4 Oct 2026 · 1 step")
    }

    func testSuggestedFileNames() {
        XCTAssertEqual(GuideFormat.pdf.suggestedFileName(for: "Set up / VPN"), "Set up - VPN.pdf")
        XCTAssertEqual(GuideFormat.html.suggestedFileName(for: "  "), "Guide.html")
        XCTAssertEqual(GuideFormat.gif.suggestedFileName(for: "Demo"), "Demo.gif")
        XCTAssertEqual(GuideFormat.markdown.suggestedFileName(for: "Demo"), "Demo")
    }

    func testPositionalImageNames() {
        XCTAssertEqual(GuideImage.fileName(step: 1, zoom: false, kind: .png), "step-01.png")
        XCTAssertEqual(GuideImage.fileName(step: 12, zoom: true, kind: .jpeg), "step-12-zoom.jpg")
        XCTAssertEqual(GuideImage.fileName(step: 100, zoom: false, kind: .png), "step-100.png")
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter ClipprTests.GuideDocumentTests`
Expected: build fails with `error: cannot find 'GuideDocument' in scope` (and similar for `ExportOptions`, `GuideFormat`, `GuideImage`).

- [ ] **Step 4: Write the implementation**

Create `Sources/Clipr/AdvancedMode/Export/GuideDocument.swift`:

```swift
// Sources/Clipr/AdvancedMode/Export/GuideDocument.swift
import Foundation

/// The five ways a reviewed session leaves Clipr. Not called `ExportFormat`: that name is the
/// image editor's PNG/JPEG "Save As…" choice.
enum GuideFormat: String, CaseIterable, Identifiable {
    case pdf, html, markdown, gif, clipboard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pdf: return "PDF"
        case .html: return "HTML"
        case .markdown: return "Markdown"
        case .gif: return "GIF"
        case .clipboard: return "Copy as Rich Text"
        }
    }

    /// The extension of the single file this format writes; nil for Markdown (a folder) and the
    /// clipboard (no file).
    var fileExtension: String? {
        switch self {
        case .pdf: return "pdf"
        case .html: return "html"
        case .gif: return "gif"
        case .markdown, .clipboard: return nil
        }
    }

    /// The save panel's starting name: the title made safe for a filename, "Guide" when nothing
    /// usable is left of it.
    func suggestedFileName(for title: String) -> String {
        let base = FilenameGenerator.sanitizedBaseName(title) ?? "Guide"
        return fileExtension.map { "\(base).\($0)" } ?? base
    }
}

/// What the export sheet chose. The title is per session; the rest is remembered by `SettingsStore`.
struct ExportOptions: Equatable {
    static let gifFrameRange: ClosedRange<Double> = 1...5

    var format: GuideFormat = .pdf
    var title: String
    var includeZoom = false
    var gifFrameSeconds: Double = 2
}

extension ImageSize {
    /// The step image's width as a whole percentage of the guide's content width.
    var widthPercent: Int { Int((widthFraction * 100).rounded()) }
}

/// Where a step's picture comes from. Rendering (annotations, downsampling, encoding) is left to
/// `GuideImages`, so building a document stays cheap and pure.
enum GuideImageRef: Equatable {
    /// A raw step PNG; its annotation sidecar sits next to it under the usual name.
    case file(URL)
    case missing
}

/// One encoded image ready to embed or write out.
struct GuideImage: Equatable {
    enum Kind: Equatable { case png, jpeg }

    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let kind: Kind

    var mimeType: String { kind == .png ? "image/png" : "image/jpeg" }

    /// Positional names ("step-01.png", "step-01-zoom.jpg"), so an export never depends on how the
    /// session's own files happen to be named.
    static func fileName(step: Int, zoom: Bool, kind: Kind) -> String {
        String(format: "step-%02d", step) + (zoom ? "-zoom" : "") + (kind == .png ? ".png" : ".jpg")
    }
}

/// Rendered images keyed by step number. Close-ups get their own map because a step can have both.
struct RenderedImages: Equatable {
    var steps: [Int: GuideImage] = [:]
    var zooms: [Int: GuideImage] = [:]
}

struct GuideStep: Equatable {
    /// 1-based position in the exported guide, not in the session.
    let number: Int
    /// Inline Markdown, untrusted; nil when the step has no caption.
    let caption: String?
    let appName: String?
    let imageSize: ImageSize
    let image: GuideImageRef
    /// Nil unless close-ups were asked for and this step has one on disk.
    let zoom: GuideImageRef?
}

/// A reviewed session reduced to what every export format needs.
struct GuideDocument: Equatable {
    let title: String
    let date: Date
    let steps: [GuideStep]

    /// The selected steps if any are still in the session, otherwise all of them, in Review order
    /// and numbered from 1. A selection that names only steps no longer in the manifest (deleted
    /// since) falls back to every step rather than exporting an empty guide.
    static func make(manifest: SessionManifest, folder: URL, selection: Set<UUID>, options: ExportOptions) -> GuideDocument {
        let live = selection.intersection(manifest.steps.map(\.id))
        let chosen = live.isEmpty ? manifest.steps : manifest.steps.filter { live.contains($0.id) }
        let steps = chosen.enumerated().map { index, record in
            GuideStep(
                number: index + 1,
                caption: nonBlank(record.caption),
                appName: nonBlank(record.appName),
                imageSize: record.imageSize ?? .full,
                image: ref(folder.appendingPathComponent(record.file)),
                zoom: options.includeZoom ? record.zoomFile.flatMap { zoomRef(folder.appendingPathComponent($0)) } : nil
            )
        }
        let title = nonBlank(options.title.split(whereSeparator: \.isNewline).joined(separator: " ")) ?? folder.lastPathComponent
        return GuideDocument(title: title, date: manifest.createdAt, steps: steps)
    }

    /// "4 Oct 2026 · 7 steps".
    var subtitle: String {
        "\(Self.dateText(date)) · \(steps.count == 1 ? "1 step" : "\(steps.count) steps")"
    }

    /// Always English day-month-year, matching the rest of Clipr's English-only copy.
    static func dateText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func ref(_ url: URL) -> GuideImageRef {
        FileManager.default.fileExists(atPath: url.path) ? .file(url) : .missing
    }

    /// A close-up whose file is gone is simply left out: it's an extra, not the step itself.
    private static func zoomRef(_ url: URL) -> GuideImageRef? {
        FileManager.default.fileExists(atPath: url.path) ? .file(url) : nil
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ClipprTests.GuideDocumentTests`
Expected: `Executed 10 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Clipr/AdvancedMode/Export/GuideDocument.swift Tests/ClipprTests/GuideDocumentTests.swift docs/superpowers/checklists/advanced-mode-capture-manual.md
git commit -m "feat: guide document model for Advanced Mode export; record clipboard spike" -m "Claude-Session: https://claude.ai/code/session_01J9DeGERVvr6uhbMe87JjkA"
```

---

### Task 2: CaptionMarkup

**Files:**
- Create: `Sources/Clipr/AdvancedMode/Export/CaptionMarkup.swift`
- Test: `Tests/ClipprTests/CaptionMarkupTests.swift`

**Interfaces:**
- Consumes: Foundation `AttributedString(markdown:options:)` with `.inlineOnlyPreservingWhitespace` (same parser `CaptionText` uses). Verified parser behaviour: raw HTML tags arrive as runs with `inlinePresentationIntent` containing `.inlineHTML`; link/image/autolink text arrives as plain runs with `link`/`imageURL` set; `\*` arrives as a literal `*`.
- Produces:
  - `enum CaptionMarkup`
    - `struct Span: Equatable { var text: String; var bold = false; var italic = false; var code = false }`
    - `static func spans(_ markdown: String?) -> [Span]`
    - `static func html(_ markdown: String?, fallbackNumber: Int) -> String`
    - `static func markdown(_ markdown: String?, fallbackNumber: Int) -> String`
    - `static func plainText(_ markdown: String?, fallbackNumber: Int) -> String`
    - `static func escapeHTML(_ text: String) -> String`
    - `static func escapeMarkdown(_ text: String) -> String`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClipprTests/CaptionMarkupTests.swift`:

```swift
// Tests/ClipprTests/CaptionMarkupTests.swift
import XCTest
@testable import Clipr

final class CaptionMarkupTests: XCTestCase {
    func testHTMLKeepsBoldItalicAndCode() {
        XCTAssertEqual(
            CaptionMarkup.html("Click **Save** in *Safari*, run `ls`", fallbackNumber: 1),
            "Click <strong>Save</strong> in <em>Safari</em>, run <code>ls</code>"
        )
    }

    func testHTMLStripsLinksImagesAndAutolinksToText() {
        XCTAssertEqual(
            CaptionMarkup.html("See [docs](https://x.com) and ![pic](a.png) <https://evil.com>", fallbackNumber: 1),
            "See docs and pic https://evil.com"
        )
        XCTAssertEqual(CaptionMarkup.html("[x](javascript:alert(1))", fallbackNumber: 1), "x")
    }

    func testHTMLDropsRawTagsAndEscapesText() {
        XCTAssertEqual(
            CaptionMarkup.html("<script>alert(1)</script> & \"q\" 'a'", fallbackNumber: 1),
            "alert(1) &amp; &quot;q&quot; &#39;a&#39;"
        )
        XCTAssertEqual(CaptionMarkup.html("Press <b>Enter</b>", fallbackNumber: 1), "Press Enter")
        XCTAssertEqual(CaptionMarkup.html("**a<b**", fallbackNumber: 1), "<strong>a&lt;b</strong>")
    }

    func testEmptyCaptionsFallBackToStepNumber() {
        for caption in [nil, "", "   ", "<br>", "**<b>**"] as [String?] {
            XCTAssertEqual(CaptionMarkup.html(caption, fallbackNumber: 4), "Step 4", "\(String(describing: caption))")
            XCTAssertEqual(CaptionMarkup.markdown(caption, fallbackNumber: 4), "Step 4")
            XCTAssertEqual(CaptionMarkup.plainText(caption, fallbackNumber: 4), "Step 4")
        }
    }

    func testNewlinesCollapseToSpaces() {
        XCTAssertEqual(CaptionMarkup.html("line1\nline2\r\nline3", fallbackNumber: 1), "line1 line2 line3")
        XCTAssertEqual(CaptionMarkup.markdown("line1\nline2", fallbackNumber: 1), "line1 line2")
    }

    func testMarkdownKeepsEmphasis() {
        XCTAssertEqual(CaptionMarkup.markdown("Click **Save** in *Safari*", fallbackNumber: 1), "Click **Save** in *Safari*")
        XCTAssertEqual(CaptionMarkup.markdown("***both***", fallbackNumber: 1), "***both***")
    }

    func testMarkdownReducesLinksImagesAndHTMLToText() {
        XCTAssertEqual(CaptionMarkup.markdown("[docs](https://x.com) ![pic](a.png) <b>hi</b>", fallbackNumber: 1), "docs pic hi")
    }

    func testMarkdownEscapesSyntaxCharacters() {
        XCTAssertEqual(CaptionMarkup.markdown("a\\*b \\[x\\] c_d", fallbackNumber: 1), "a\\*b \\[x\\] c\\_d")
        XCTAssertEqual(CaptionMarkup.markdown("back\\\\slash", fallbackNumber: 1), "back\\\\slash")
        XCTAssertEqual(CaptionMarkup.markdown("a ` b", fallbackNumber: 1), "a \\` b")
        XCTAssertEqual(CaptionMarkup.markdown("1 < 2 > 0", fallbackNumber: 1), "1 \\< 2 \\> 0")
        // CaptionFormatter writes a UI label's "*" as "\*" inside bold; it must stay literal.
        XCTAssertEqual(CaptionMarkup.markdown("Click **a\\*b**", fallbackNumber: 1), "Click **a\\*b**")
    }

    func testMarkdownCodeSpanSurvivesBackticks() {
        XCTAssertEqual(CaptionMarkup.markdown("Run `ls -la`", fallbackNumber: 1), "Run `ls -la`")
        XCTAssertEqual(CaptionMarkup.markdown("``a`b``", fallbackNumber: 1), "``a`b``")
    }

    func testPlainTextDropsEmphasis() {
        XCTAssertEqual(CaptionMarkup.plainText("Click **Save** in [Safari](https://x)", fallbackNumber: 1), "Click Save in Safari")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipprTests.CaptionMarkupTests`
Expected: build fails with `error: cannot find 'CaptionMarkup' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Clipr/AdvancedMode/Export/CaptionMarkup.swift`:

```swift
// Sources/Clipr/AdvancedMode/Export/CaptionMarkup.swift
import Foundation

/// Step captions are inline Markdown partly built from other apps' Accessibility labels, so they
/// are untrusted. Every export keeps bold, italic and code and turns everything else — links,
/// images, autolinks, raw HTML — into plain text, the rule `CaptionText` applies in Review.
enum CaptionMarkup {
    /// One stretch of caption text and the emphasis kept on it.
    struct Span: Equatable {
        var text: String
        var bold = false
        var italic = false
        var code = false
    }

    /// The caption parsed into spans. Line breaks become spaces, since every format shows a caption
    /// as a one-line heading (a newline would end a Markdown heading early). Raw HTML tags are
    /// dropped and the text between them kept. Empty when nothing visible is left.
    static func spans(_ markdown: String?) -> [Span] {
        guard let markdown else { return [] }
        let flattened = markdown.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard let parsed = try? AttributedString(
            markdown: flattened,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return flattened.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [Span(text: flattened)]
        }
        var result: [Span] = []
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.inlineHTML) { continue }
            let text = String(parsed[run.range].characters)
            guard !text.isEmpty else { continue }
            let span = Span(text: text, bold: intent.contains(.stronglyEmphasized),
                            italic: intent.contains(.emphasized), code: intent.contains(.code))
            // A link's text arrives as its own run; merging it back keeps the output tidy.
            if let last = result.last, last.bold == span.bold, last.italic == span.italic, last.code == span.code {
                result[result.count - 1].text += span.text
            } else {
                result.append(span)
            }
        }
        if result.allSatisfy({ $0.text.trimmingCharacters(in: .whitespaces).isEmpty }) { return [] }
        return result
    }

    /// The caption as HTML: `<strong>`, `<em>` and `<code>` only, every character of text escaped.
    static func html(_ markdown: String?, fallbackNumber: Int) -> String {
        let parts = spans(markdown)
        guard !parts.isEmpty else { return "Step \(fallbackNumber)" }
        return parts.map { span in
            var text = escapeHTML(span.text)
            if span.code { text = "<code>\(text)</code>" }
            if span.italic { text = "<em>\(text)</em>" }
            if span.bold { text = "<strong>\(text)</strong>" }
            return text
        }.joined()
    }

    /// The caption as Markdown that can't turn into a link, image or HTML wherever it's rendered.
    static func markdown(_ markdown: String?, fallbackNumber: Int) -> String {
        let parts = spans(markdown)
        guard !parts.isEmpty else { return "Step \(fallbackNumber)" }
        return parts.map { span in
            var text = span.code ? codeSpan(span.text) : escapeMarkdown(span.text)
            if span.italic { text = "*\(text)*" }
            if span.bold { text = "**\(text)**" }
            return text
        }.joined()
    }

    /// The caption's words alone, for the GIF's caption band.
    static func plainText(_ markdown: String?, fallbackNumber: Int) -> String {
        let parts = spans(markdown)
        return parts.isEmpty ? "Step \(fallbackNumber)" : parts.map(\.text).joined()
    }

    static func escapeHTML(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }

    /// Backslash-escapes every character that could start Markdown syntax inside a heading line.
    /// `*` is included alongside the spec's list: captions carry literal asterisks (CaptionFormatter
    /// escapes them in UI labels) that would otherwise turn into emphasis.
    static func escapeMarkdown(_ text: String) -> String {
        let special: Set<Character> = ["\\", "`", "*", "_", "[", "]", "<", ">"]
        var out = ""
        for character in text {
            if special.contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }

    /// A code span whose fence is longer than any run of backticks inside it, so the code can't
    /// close its own span.
    private static func codeSpan(_ text: String) -> String {
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: longest + 1)
        let pad = text.hasPrefix("`") || text.hasSuffix("`") ? " " : ""
        return fence + pad + text + pad + fence
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClipprTests.CaptionMarkupTests`
Expected: `Executed 10 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/Export/CaptionMarkup.swift Tests/ClipprTests/CaptionMarkupTests.swift
git commit -m "feat: safe caption rendering to HTML, Markdown and plain text for export" -m "Claude-Session: https://claude.ai/code/session_01J9DeGERVvr6uhbMe87JjkA"
```

---

### Task 3: HTMLGuideWriter

**Files:**
- Create: `Sources/Clipr/AdvancedMode/Export/HTMLGuideWriter.swift`
- Test: `Tests/ClipprTests/HTMLGuideWriterTests.swift`

**Interfaces:**
- Consumes: Task 1 `GuideDocument`, `GuideStep`, `GuideImage` (`mimeType`, `fileName(step:zoom:kind:)`), `RenderedImages`, `ImageSize.widthPercent`, `GuideDocument.subtitle`; Task 2 `CaptionMarkup.html(_:fallbackNumber:)`, `CaptionMarkup.escapeHTML(_:)`.
- Produces:
  - `enum HTMLImageMode: Equatable { case embedded; case linked(prefix: String) }`
  - `enum HTMLGuideWriter { static let zoomWidthPercent = 30; static func write(_ doc: GuideDocument, images: RenderedImages, mode: HTMLImageMode) -> String; static let css: String }`
  - Markup contract later tasks and tests rely on: `<h1>title</h1>`, `<p class="meta">subtitle</p>`, per step `<section class="step">` → `<h2><span class="num">N</span><span class="caption">…</span></h2>`, optional `<p class="app">`, `<div class="figure">` holding `<img class="shot|zoom" src="…" alt="Step N[ close-up]" style="width:P%">` or `<div class="shot|zoom missing" style="width:P%">Image unavailable</div>`.

- [ ] **Step 1: Write the failing test**

Create `Tests/ClipprTests/HTMLGuideWriterTests.swift`:

```swift
// Tests/ClipprTests/HTMLGuideWriterTests.swift
import XCTest
@testable import Clipr

final class HTMLGuideWriterTests: XCTestCase {
    let date = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!
    let png = GuideImage(data: Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]), pixelWidth: 10, pixelHeight: 5, kind: .png)
    let zoomJPEG = GuideImage(data: Data([0xFF, 0xD8, 9]), pixelWidth: 4, pixelHeight: 4, kind: .jpeg)
    let somewhere = GuideImageRef.file(URL(fileURLWithPath: "/unused.png"))

    private func doc(title: String = "My Guide", captions: [String?] = ["Heading A", "Heading B", nil],
                     app: String? = "Safari") -> GuideDocument {
        let sizes: [ImageSize] = [.full, .medium, .small]
        let steps = captions.enumerated().map { index, caption in
            GuideStep(number: index + 1, caption: caption, appName: app, imageSize: sizes[index % 3],
                      image: somewhere, zoom: index == 0 ? somewhere : nil)
        }
        return GuideDocument(title: title, date: date, steps: steps)
    }

    /// Step 1 and 2 rendered, step 3's image missing; step 1 has a close-up.
    private var images: RenderedImages {
        RenderedImages(steps: [1: png, 2: png], zooms: [1: zoomJPEG])
    }

    func testHeaderHasTitleDateAndCount() {
        let html = HTMLGuideWriter.write(doc(), images: images, mode: .embedded)
        XCTAssertTrue(html.contains("<title>My Guide</title>"))
        XCTAssertTrue(html.contains("<h1>My Guide</h1>"))
        XCTAssertTrue(html.contains("<p class=\"meta\">4 Oct 2026 · 3 steps</p>"))
    }

    func testStepsInOrderWithNumbersAndFallbackHeading() throws {
        let html = HTMLGuideWriter.write(doc(), images: images, mode: .embedded)
        let a = try XCTUnwrap(html.range(of: "<span class=\"num\">1</span><span class=\"caption\">Heading A</span>"))
        let b = try XCTUnwrap(html.range(of: "<span class=\"num\">2</span><span class=\"caption\">Heading B</span>"))
        let c = try XCTUnwrap(html.range(of: "<span class=\"num\">3</span><span class=\"caption\">Step 3</span>"))
        XCTAssertLessThan(a.lowerBound, b.lowerBound)
        XCTAssertLessThan(b.lowerBound, c.lowerBound)
        XCTAssertTrue(html.contains("<p class=\"app\">Safari</p>"))
    }

    func testWidthFollowsImageSize() {
        let html = HTMLGuideWriter.write(doc(), images: images, mode: .embedded)
        XCTAssertTrue(html.contains("alt=\"Step 1\" style=\"width:100%\""))
        XCTAssertTrue(html.contains("alt=\"Step 2\" style=\"width:60%\""))
        XCTAssertTrue(html.contains("<div class=\"shot missing\" style=\"width:40%\">Image unavailable</div>"))
    }

    func testEmbeddedImagesAreDataURIs() {
        let html = HTMLGuideWriter.write(doc(), images: images, mode: .embedded)
        XCTAssertTrue(html.contains("src=\"data:image/png;base64,\(png.data.base64EncodedString())\""))
        XCTAssertTrue(html.contains("src=\"data:image/jpeg;base64,\(zoomJPEG.data.base64EncodedString())\""))
    }

    func testLinkedImagesUsePositionalPaths() {
        let html = HTMLGuideWriter.write(doc(), images: images, mode: .linked(prefix: "images/"))
        XCTAssertTrue(html.contains("<img class=\"shot\" src=\"images/step-01.png\" alt=\"Step 1\""))
        XCTAssertTrue(html.contains("<img class=\"zoom\" src=\"images/step-01-zoom.jpg\" alt=\"Step 1 close-up\" style=\"width:30%\">"))
        XCTAssertFalse(html.contains("data:"))
    }

    func testCloseUpOnlyForStepsThatHaveOne() {
        let html = HTMLGuideWriter.write(doc(), images: images, mode: .embedded)
        XCTAssertTrue(html.contains("alt=\"Step 1 close-up\""))
        XCTAssertFalse(html.contains("alt=\"Step 2 close-up\""))
    }

    func testStepsAvoidPageBreaks() {
        XCTAssertTrue(HTMLGuideWriter.css.contains(".step { break-inside: avoid; page-break-inside: avoid;"))
    }

    func testHostileCaptionsProduceNoActiveContent() {
        let hostile = doc(
            title: "<script>alert('t')</script>",
            captions: ["<script>alert(1)</script>", "[x](javascript:alert(1))", "<img src=x onerror=alert(1)>"],
            app: "\"><svg onload=alert(1)>"
        )
        for mode in [HTMLImageMode.embedded, .linked(prefix: "\"><script>")] {
            let html = HTMLGuideWriter.write(hostile, images: images, mode: mode).lowercased()
            XCTAssertFalse(html.contains("<script"), "\(mode)")
            XCTAssertFalse(html.contains("<svg"), "\(mode)")
            let activeAttribute = try! NSRegularExpression(pattern: "<[^>]*(\\son[a-z]+\\s*=|javascript:)[^>]*>")
            XCTAssertNil(activeAttribute.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), "\(mode)")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipprTests.HTMLGuideWriterTests`
Expected: build fails with `error: cannot find 'HTMLGuideWriter' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Clipr/AdvancedMode/Export/HTMLGuideWriter.swift`:

```swift
// Sources/Clipr/AdvancedMode/Export/HTMLGuideWriter.swift
import Foundation

/// How the HTML refers to step images: inline data URIs (one self-contained file, also what the
/// PDF and the clipboard use) or relative paths under `prefix`.
enum HTMLImageMode: Equatable {
    case embedded
    case linked(prefix: String)
}

/// The one guide template behind HTML, PDF and the clipboard. Light theme and the system font
/// stack only, so it looks the same printed, opened in a browser and pasted into a docs tool.
enum HTMLGuideWriter {
    /// A close-up sits beside its step image at this share of the content width.
    static let zoomWidthPercent = 30

    static func write(_ doc: GuideDocument, images: RenderedImages, mode: HTMLImageMode) -> String {
        var html = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(CaptionMarkup.escapeHTML(doc.title))</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <main class="guide">
        <header><h1>\(CaptionMarkup.escapeHTML(doc.title))</h1><p class="meta">\(CaptionMarkup.escapeHTML(doc.subtitle))</p></header>

        """
        for step in doc.steps {
            html += stepHTML(step, images: images, mode: mode)
        }
        html += "</main>\n</body>\n</html>\n"
        return html
    }

    private static func stepHTML(_ step: GuideStep, images: RenderedImages, mode: HTMLImageMode) -> String {
        let number = step.number
        var html = "<section class=\"step\">\n"
        html += "<h2><span class=\"num\">\(number)</span><span class=\"caption\">"
        html += CaptionMarkup.html(step.caption, fallbackNumber: number)
        html += "</span></h2>\n"
        if let app = step.appName {
            html += "<p class=\"app\">\(CaptionMarkup.escapeHTML(app))</p>\n"
        }
        html += "<div class=\"figure\">\n"
        html += imageHTML(images.steps[number], step: number, zoom: false, alt: "Step \(number)",
                          width: step.imageSize.widthPercent, mode: mode)
        if step.zoom != nil {
            html += imageHTML(images.zooms[number], step: number, zoom: true, alt: "Step \(number) close-up",
                              width: zoomWidthPercent, mode: mode)
        }
        html += "</div>\n</section>\n"
        return html
    }

    private static func imageHTML(_ image: GuideImage?, step: Int, zoom: Bool, alt: String, width: Int, mode: HTMLImageMode) -> String {
        let role = zoom ? "zoom" : "shot"
        guard let image else {
            return "<div class=\"\(role) missing\" style=\"width:\(width)%\">Image unavailable</div>\n"
        }
        let src: String
        switch mode {
        case .embedded:
            src = "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"
        case .linked(let prefix):
            src = CaptionMarkup.escapeHTML(prefix + GuideImage.fileName(step: step, zoom: zoom, kind: image.kind))
        }
        return "<img class=\"\(role)\" src=\"\(src)\" alt=\"\(alt)\" style=\"width:\(width)%\">\n"
    }

    /// `break-inside: avoid` keeps each step on one page when WebKit prints the PDF; the print-only
    /// `max-height` shrinks a tall image to fit the page instead of letting the step split.
    static let css = """
    :root { color-scheme: light; }
    body { margin: 0; background: #fff; color: #1d1d1f; font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
    .guide { max-width: 860px; margin: 0 auto; padding: 32px 24px; }
    h1 { font-size: 28px; line-height: 1.2; margin: 0 0 4px; }
    .meta { color: #6e6e73; margin: 0 0 28px; }
    .step { break-inside: avoid; page-break-inside: avoid; margin: 0 0 32px; }
    .step h2 { display: flex; align-items: baseline; gap: 10px; font-size: 18px; font-weight: 400; margin: 0 0 2px; }
    .num { flex: none; display: inline-flex; align-items: center; justify-content: center; width: 26px; height: 26px; border-radius: 50%; background: #0a84ff; color: #fff; font-size: 14px; font-weight: 600; }
    .app { color: #8e8e93; font-size: 12px; margin: 0 0 8px 36px; }
    .figure { display: flex; flex-wrap: wrap; gap: 12px; align-items: flex-start; margin-top: 8px; }
    .figure > * { flex: none; box-sizing: border-box; max-width: 100%; border: 1px solid #d2d2d7; border-radius: 6px; }
    .figure img { display: block; height: auto; }
    .missing { display: flex; align-items: center; justify-content: center; min-height: 120px; background: #f2f2f4; color: #8e8e93; }
    code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.9em; background: #f2f2f4; padding: 1px 4px; border-radius: 4px; }
    @media print {
      .guide { max-width: none; padding: 0; }
      .figure img { max-height: 200mm; object-fit: contain; object-position: left top; }
    }
    """
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClipprTests.HTMLGuideWriterTests`
Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/Export/HTMLGuideWriter.swift Tests/ClipprTests/HTMLGuideWriterTests.swift
git commit -m "feat: HTML guide template for export" -m "Claude-Session: https://claude.ai/code/session_01J9DeGERVvr6uhbMe87JjkA"
```

---

### Task 4: MarkdownGuideWriter

**Files:**
- Create: `Sources/Clipr/AdvancedMode/Export/MarkdownGuideWriter.swift`
- Test: `Tests/ClipprTests/MarkdownGuideWriterTests.swift`

**Interfaces:**
- Consumes: Task 1 `GuideDocument`, `GuideStep`, `GuideImage.fileName(step:zoom:kind:)`, `RenderedImages`, `ImageSize.widthPercent`; Task 2 `CaptionMarkup.markdown(_:fallbackNumber:)`, `CaptionMarkup.escapeMarkdown(_:)`.
- Produces:
  - `enum MarkdownGuideWriter { static let fileName = "guide.md"; static let imagesFolder = "images"; static func write(_ doc: GuideDocument, images: RenderedImages) -> String; static func export(_ doc: GuideDocument, images: RenderedImages, to folder: URL) throws; static func hasExistingGuide(in folder: URL) -> Bool }`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClipprTests/MarkdownGuideWriterTests.swift`:

```swift
// Tests/ClipprTests/MarkdownGuideWriterTests.swift
import XCTest
@testable import Clipr

final class MarkdownGuideWriterTests: XCTestCase {
    var folder: URL!
    let date = ISO8601DateFormatter().date(from: "2026-10-04T12:00:00Z")!
    let png = GuideImage(data: Data([0x89, 0x50, 1]), pixelWidth: 10, pixelHeight: 5, kind: .png)
    let jpeg = GuideImage(data: Data([0xFF, 0xD8, 2]), pixelWidth: 10, pixelHeight: 5, kind: .jpeg)
    let somewhere = GuideImageRef.file(URL(fileURLWithPath: "/unused.png"))

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var doc: GuideDocument {
        GuideDocument(title: "Set up VPN", date: date, steps: [
            GuideStep(number: 1, caption: "Click **Save** in Safari", appName: "Safari", imageSize: .full, image: somewhere, zoom: somewhere),
            GuideStep(number: 2, caption: "Click in **Warp**", appName: nil, imageSize: .medium, image: somewhere, zoom: nil),
            GuideStep(number: 3, caption: nil, appName: nil, imageSize: .small, image: .missing, zoom: nil),
        ])
    }

    private var images: RenderedImages { RenderedImages(steps: [1: png, 2: jpeg], zooms: [1: png]) }

    func testDocumentLayout() {
        XCTAssertEqual(MarkdownGuideWriter.write(doc, images: images), """
        # Set up VPN
        _4 Oct 2026 · 3 steps_

        ## 1. Click **Save** in Safari
        ![Step 1](images/step-01.png)

        ![Step 1 close-up](images/step-01-zoom.png)

        ## 2. Click in **Warp**
        <img src="images/step-02.jpg" alt="Step 2" width="60%">

        ## 3. Step 3
        _Image unavailable_

        """)
    }

    func testMultiLineCaptionStaysInHeading() {
        let multi = GuideDocument(title: "T", date: date, steps: [
            GuideStep(number: 1, caption: "Click **Save**\n# not a heading", appName: nil, imageSize: .full, image: somewhere, zoom: nil),
        ])
        let lines = MarkdownGuideWriter.write(multi, images: images).components(separatedBy: "\n")
        XCTAssertEqual(lines[3], "## 1. Click **Save** # not a heading")
        XCTAssertEqual(lines[4], "![Step 1](images/step-01.png)")
    }

    func testTitleIsEscaped() {
        let titled = GuideDocument(title: "[Draft] <b>", date: date, steps: [])
        XCTAssertTrue(MarkdownGuideWriter.write(titled, images: RenderedImages()).hasPrefix("# \\[Draft\\] \\<b\\>\n"))
    }

    func testExportWritesGuideAndPositionalImages() throws {
        try MarkdownGuideWriter.export(doc, images: images, to: folder)
        let guide = try String(contentsOf: folder.appendingPathComponent("guide.md"), encoding: .utf8)
        XCTAssertEqual(guide, MarkdownGuideWriter.write(doc, images: images))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("images").path).sorted()
        XCTAssertEqual(names, ["step-01-zoom.png", "step-01.png", "step-02.jpg"])
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("images/step-02.jpg")), jpeg.data)
    }

    func testHasExistingGuide() throws {
        XCTAssertFalse(MarkdownGuideWriter.hasExistingGuide(in: folder))
        try MarkdownGuideWriter.export(doc, images: images, to: folder)
        XCTAssertTrue(MarkdownGuideWriter.hasExistingGuide(in: folder))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipprTests.MarkdownGuideWriterTests`
Expected: build fails with `error: cannot find 'MarkdownGuideWriter' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Clipr/AdvancedMode/Export/MarkdownGuideWriter.swift`:

```swift
// Sources/Clipr/AdvancedMode/Export/MarkdownGuideWriter.swift
import Foundation

/// A Markdown guide for GitHub, MkDocs, wikis and Notion import: `guide.md` plus an `images/`
/// folder it links to relatively, so the folder can be moved or committed as it is.
enum MarkdownGuideWriter {
    static let fileName = "guide.md"
    static let imagesFolder = "images"

    static func write(_ doc: GuideDocument, images: RenderedImages) -> String {
        var lines = ["# \(CaptionMarkup.escapeMarkdown(doc.title))", "_\(doc.subtitle)_", ""]
        for step in doc.steps {
            let number = step.number
            lines.append("## \(number). \(CaptionMarkup.markdown(step.caption, fallbackNumber: number))")
            lines.append(imageLine(images.steps[number], step: number, zoom: false, alt: "Step \(number)", size: step.imageSize))
            if step.zoom != nil {
                lines.append("")
                lines.append(imageLine(images.zooms[number], step: number, zoom: true, alt: "Step \(number) close-up", size: .full))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Writes `guide.md` and `images/` into `folder`, creating it if needed.
    static func export(_ doc: GuideDocument, images: RenderedImages, to folder: URL) throws {
        let imagesURL = folder.appendingPathComponent(imagesFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        for step in doc.steps {
            if let image = images.steps[step.number] {
                try image.data.write(to: imagesURL.appendingPathComponent(GuideImage.fileName(step: step.number, zoom: false, kind: image.kind)))
            }
            if step.zoom != nil, let zoom = images.zooms[step.number] {
                try zoom.data.write(to: imagesURL.appendingPathComponent(GuideImage.fileName(step: step.number, zoom: true, kind: zoom.kind)))
            }
        }
        try Data(write(doc, images: images).utf8).write(to: folder.appendingPathComponent(fileName))
    }

    /// Whether exporting into `folder` would overwrite an earlier guide, so the user is asked first.
    static func hasExistingGuide(in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(fileName).path)
    }

    /// Markdown image syntax has no width, so sized steps use an `<img>` tag, which GitHub, MkDocs
    /// and most wikis render; Full steps keep plain Markdown.
    private static func imageLine(_ image: GuideImage?, step: Int, zoom: Bool, alt: String, size: ImageSize) -> String {
        guard let image else { return "_Image unavailable_" }
        let path = "\(imagesFolder)/\(GuideImage.fileName(step: step, zoom: zoom, kind: image.kind))"
        if size == .full { return "![\(alt)](\(path))" }
        return "<img src=\"\(path)\" alt=\"\(alt)\" width=\"\(size.widthPercent)%\">"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClipprTests.MarkdownGuideWriterTests`
Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/Export/MarkdownGuideWriter.swift Tests/ClipprTests/MarkdownGuideWriterTests.swift
git commit -m "feat: Markdown guide export with relative image links" -m "Claude-Session: https://claude.ai/code/session_01J9DeGERVvr6uhbMe87JjkA"
```

---

### Task 5: GuideImages

**Files:**
- Create: `Sources/Clipr/AdvancedMode/Export/GuideImages.swift`
- Test: `Tests/ClipprTests/GuideImagesTests.swift`

**Interfaces:**
- Consumes: Task 1 `GuideImageRef`, `GuideImage`; existing `StorageManager(baseFolder:)` + `readAnnotations(rawURL:) -> AnnotationsLoad` (`.missing` / `.loaded([AnnotationObject])` / `.corrupt(Error)` — `loadAnnotations` can't tell corrupt from missing, so it isn't used), `AnnotationRenderer.flatten(base:annotations:) -> NSImage`, `NSImage.bitmap`; tests use `testImage(width:height:scale:_:)`, `StepFiles.pngData(_:)`, `FilenameGenerator.annotationsName(fromRaw:)`, `StorageManager.saveAnnotations(_:rawURL:)`.
- Produces:
  - `struct GuideImageRender { let image: GuideImage?; let sidecarDamaged: Bool }`
  - `enum GuideImages { static let fullPixelWidth = 1600; static let zoomPixelWidth = 480; static let jpegThreshold = 1_500_000; static let jpegQuality = 0.85; static func maxPixelWidth(for size: ImageSize) -> Int; static func render(_ ref: GuideImageRef, maxPixelWidth: Int, jpegThreshold: Int = GuideImages.jpegThreshold) -> GuideImageRender; static func downsampled(_ image: CGImage, maxPixelWidth: Int) -> CGImage?; static func encode(_ image: CGImage, jpegThreshold: Int = GuideImages.jpegThreshold) -> GuideImage? }`
  - Thread-safe: callable off the main thread.

- [ ] **Step 1: Write the failing test**

Create `Tests/ClipprTests/GuideImagesTests.swift`:

```swift
// Tests/ClipprTests/GuideImagesTests.swift
import XCTest
import Cocoa
@testable import Clipr

final class GuideImagesTests: XCTestCase {
    var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Writes `image` as a step PNG the way capture does, returning its URL.
    private func writeStep(_ image: NSImage, name: String = "Step_01.png") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try XCTUnwrap(StepFiles.pngData(image)).write(to: url)
        return url
    }

    private func white(width: Int, height: Int, scale: CGFloat = 1) -> NSImage {
        testImage(width: width, height: height, scale: scale) {
            NSColor.white.set()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
    }

    /// Random pixels: the worst case for PNG, so its encoding is far larger than a JPEG's.
    private func noise(width: Int, height: Int) -> NSImage {
        let bytes = (0..<(width * height * 4)).map { $0 % 4 == 3 ? UInt8(255) : UInt8.random(in: 0...255) }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }

    private func decode(_ image: GuideImage?) throws -> NSBitmapImageRep {
        try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image).data))
    }

    func testFlattensAnnotationsOntoImage() throws {
        let url = try writeStep(white(width: 40, height: 40))
        let box = AnnotationObject(id: UUID(), kind: .blur, frame: CGRect(x: 10, y: 10, width: 20, height: 20),
                                   color: RGBAColor(red: 1, green: 0, blue: 0, alpha: 1), strokeWidth: 2, redactionStyle: .solid)
        try StorageManager(baseFolder: folder).saveAnnotations([box], rawURL: url)

        let result = GuideImages.render(.file(url), maxPixelWidth: 1600)
        XCTAssertFalse(result.sidecarDamaged)
        let bitmap = try decode(result.image)
        XCTAssertLessThan(try XCTUnwrap(bitmap.colorAt(x: 20, y: 20)).brightnessComponent, 0.3, "redaction drawn in the middle")
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 2, y: 2)).brightnessComponent, 0.9, "corner untouched")
    }

    func testDownsamplesToMaxWidth() throws {
        let url = try writeStep(white(width: 3000, height: 100))
        let image = try XCTUnwrap(GuideImages.render(.file(url), maxPixelWidth: 1600).image)
        XCTAssertEqual(image.pixelWidth, 1600)
        XCTAssertEqual(image.pixelHeight, 53)
    }

    func testNeverEnlarges() throws {
        let url = try writeStep(white(width: 300, height: 100))
        let image = try XCTUnwrap(GuideImages.render(.file(url), maxPixelWidth: 1600).image)
        XCTAssertEqual(image.pixelWidth, 300)
    }

    func testRetinaImageCapsPixelsNotPoints() throws {
        // 100×50 points, 200×100 pixels: the cap applies to the pixels.
        let url = try writeStep(white(width: 100, height: 50, scale: 2))
        let capped = try XCTUnwrap(GuideImages.render(.file(url), maxPixelWidth: 150).image)
        XCTAssertEqual(capped.pixelWidth, 150)
        XCTAssertEqual(capped.pixelHeight, 75)
        let full = try XCTUnwrap(GuideImages.render(.file(url), maxPixelWidth: 1600).image)
        XCTAssertEqual(full.pixelWidth, 200, "every Retina pixel kept when there's room")
    }

    func testWidthsPerSize() {
        XCTAssertEqual(ImageSize.allCases.map(GuideImages.maxPixelWidth(for:)), [640, 960, 1280, 1600])
        XCTAssertEqual(GuideImages.jpegThreshold, 1_500_000)
        XCTAssertEqual(GuideImages.zoomPixelWidth, 480)
    }

    func testSmallImageStaysPNG() throws {
        let url = try writeStep(white(width: 50, height: 50))
        let image = try XCTUnwrap(GuideImages.render(.file(url), maxPixelWidth: 1600).image)
        XCTAssertEqual(image.kind, .png)
        XCTAssertEqual(Array(image.data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    func testLargePNGFallsBackToJPEG() throws {
        let url = try writeStep(noise(width: 200, height: 200))
        let image = try XCTUnwrap(GuideImages.render(.file(url), maxPixelWidth: 1600, jpegThreshold: 1_000).image)
        XCTAssertEqual(image.kind, .jpeg)
        XCTAssertEqual(Array(image.data.prefix(2)), [0xFF, 0xD8])
        XCTAssertEqual(image.pixelWidth, 200)
    }

    func testDamagedSidecarGivesRawImageAndFlag() throws {
        let url = try writeStep(white(width: 20, height: 20))
        try Data("not json".utf8).write(to: folder.appendingPathComponent(FilenameGenerator.annotationsName(fromRaw: "Step_01.png")))
        let result = GuideImages.render(.file(url), maxPixelWidth: 1600)
        XCTAssertTrue(result.sidecarDamaged)
        XCTAssertEqual(result.image?.pixelWidth, 20)
    }

    func testMissingOrUnreadableImageGivesNil() throws {
        XCTAssertNil(GuideImages.render(.missing, maxPixelWidth: 1600).image)
        XCTAssertNil(GuideImages.render(.file(folder.appendingPathComponent("nope.png")), maxPixelWidth: 1600).image)
        let garbage = folder.appendingPathComponent("Step_09.png")
        try Data([1, 2, 3]).write(to: garbage)
        let result = GuideImages.render(.file(garbage), maxPixelWidth: 1600)
        XCTAssertNil(result.image)
        XCTAssertFalse(result.sidecarDamaged)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipprTests.GuideImagesTests`
Expected: build fails with `error: cannot find 'GuideImages' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Clipr/AdvancedMode/Export/GuideImages.swift`:

```swift
// Sources/Clipr/AdvancedMode/Export/GuideImages.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The outcome of rendering one step image.
struct GuideImageRender {
    /// Nil when the image is missing or won't decode.
    let image: GuideImage?
    /// The step's annotation sidecar exists but couldn't be read, so `image` is the raw capture.
    let sidecarDamaged: Bool
}

/// Turns a step's raw PNG into the picture an export shows: annotations flattened on (as Review
/// and the editor show it), scaled down to what a guide needs, and encoded small enough to embed.
/// Safe to call off the main thread: everything is drawn into explicit CGContexts.
enum GuideImages {
    /// A Full-width step's width in pixels; sized steps get their share of it.
    static let fullPixelWidth = 1600
    /// Close-ups sit at 30% of the content width.
    static let zoomPixelWidth = 480
    /// Above this a PNG is re-encoded as JPEG, so a photo-like screenshot doesn't bloat the guide.
    static let jpegThreshold = 1_500_000
    static let jpegQuality = 0.85

    static func maxPixelWidth(for size: ImageSize) -> Int {
        Int((CGFloat(fullPixelWidth) * size.widthFraction).rounded())
    }

    static func render(_ ref: GuideImageRef, maxPixelWidth: Int, jpegThreshold: Int = GuideImages.jpegThreshold) -> GuideImageRender {
        guard case .file(let url) = ref, let base = NSImage(contentsOf: url), base.bitmap != nil else {
            return GuideImageRender(image: nil, sidecarDamaged: false)
        }
        var annotations: [AnnotationObject] = []
        var damaged = false
        switch StorageManager(baseFolder: url.deletingLastPathComponent()).readAnnotations(rawURL: url) {
        case .loaded(let loaded): annotations = loaded
        case .corrupt: damaged = true
        case .missing: break
        }
        let flat = annotations.isEmpty ? base : AnnotationRenderer.flatten(base: base, annotations: annotations)
        guard let bitmap = flat.bitmap, let scaled = downsampled(bitmap, maxPixelWidth: maxPixelWidth) else {
            return GuideImageRender(image: nil, sidecarDamaged: damaged)
        }
        return GuideImageRender(image: encode(scaled, jpegThreshold: jpegThreshold), sidecarDamaged: damaged)
    }

    /// `image` no wider than `maxPixelWidth` pixels (never enlarged), aspect ratio kept. Pixels,
    /// not points: a Retina capture is twice as many pixels as its point size.
    static func downsampled(_ image: CGImage, maxPixelWidth: Int) -> CGImage? {
        guard maxPixelWidth > 0, image.width > maxPixelWidth else { return image }
        let width = maxPixelWidth
        let height = max(1, Int((CGFloat(image.height) * CGFloat(width) / CGFloat(image.width)).rounded()))
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// PNG, or JPEG when the PNG would be larger than `jpegThreshold` bytes.
    static func encode(_ image: CGImage, jpegThreshold: Int = GuideImages.jpegThreshold) -> GuideImage? {
        guard let png = encoded(image, as: .png, properties: [:]) else { return nil }
        let pngImage = GuideImage(data: png, pixelWidth: image.width, pixelHeight: image.height, kind: .png)
        guard png.count > jpegThreshold else { return pngImage }
        guard let opaque = onWhite(image),
              let jpeg = encoded(opaque, as: .jpeg, properties: [kCGImageDestinationLossyCompressionQuality: jpegQuality])
        else { return pngImage }
        return GuideImage(data: jpeg, pixelWidth: image.width, pixelHeight: image.height, kind: .jpeg)
    }

    private static func encoded(_ image: CGImage, as type: UTType, properties: [CFString: Any]) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// JPEG has no alpha: transparent areas (a canvas the editor enlarged) would turn black.
    private static func onWhite(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClipprTests.GuideImagesTests`
Expected: `Executed 9 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/Export/GuideImages.swift Tests/ClipprTests/GuideImagesTests.swift
git commit -m "feat: render step images for export with annotations, downsampling and JPEG fallback" -m "Claude-Session: https://claude.ai/code/session_01J9DeGERVvr6uhbMe87JjkA"
```

---

### Task 6: GIFGuideExporter

**Files:**
- Create: `Sources/Clipr/AdvancedMode/Export/GIFGuideExporter.swift`
- Test: `Tests/ClipprTests/GIFGuideExporterTests.swift`

**Interfaces:**
- Consumes: Task 1 `GuideDocument`, `GuideImage`, `RenderedImages`, `ExportOptions.gifFrameRange`; Task 2 `CaptionMarkup.plainText(_:fallbackNumber:)`; Task 5 `GuideImages.encode(_:)` (tests).
- Produces:
  - `enum GIFGuideExporter { static let maxCanvasWidth = 1000; static let minCanvasWidth = 480; static let captionBandHeight = 72; static let placeholderHeight = 400; enum GIFError: Error { case cannotCreate, encodeFailed }; static func clampedFrameSeconds(_ seconds: Double) -> Double; static func canvasSize(for images: [GuideImage?]) -> CGSize; static func fittedSize(_ image: GuideImage, width: Int) -> (width: Int, height: Int); static func export(_ doc: GuideDocument, images: RenderedImages, frameSeconds: Double, to url: URL) throws; static func renderFrame(_ image: GuideImage?, caption: String, canvas: CGSize) -> CGImage? }`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClipprTests/GIFGuideExporterTests.swift`:

```swift
// Tests/ClipprTests/GIFGuideExporterTests.swift
import XCTest
import Cocoa
import ImageIO
@testable import Clipr

final class GIFGuideExporterTests: XCTestCase {
    var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gif")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func solid(width: Int, height: Int) throws -> GuideImage {
        let image = testImage(width: width, height: height) {
            NSColor.systemBlue.set()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
        }
        return try XCTUnwrap(GuideImages.encode(try XCTUnwrap(image.bitmap)))
    }

    /// Three steps: a wide image, a tall one, and one whose image is missing.
    private func export(frameSeconds: Double) throws {
        let somewhere = GuideImageRef.file(URL(fileURLWithPath: "/unused.png"))
        let doc = GuideDocument(title: "GIF", date: Date(), steps: [
            GuideStep(number: 1, caption: "Click **Save**", appName: nil, imageSize: .full, image: somewhere, zoom: nil),
            GuideStep(number: 2, caption: nil, appName: nil, imageSize: .small, image: somewhere, zoom: nil),
            GuideStep(number: 3, caption: "Done", appName: nil, imageSize: .full, image: .missing, zoom: nil),
        ])
        let images = RenderedImages(steps: [1: try solid(width: 1200, height: 600), 2: try solid(width: 800, height: 800)])
        try GIFGuideExporter.export(doc, images: images, frameSeconds: frameSeconds, to: url)
    }

    private func source() throws -> CGImageSource {
        try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    }

    private func delay(of frame: Int, in source: CGImageSource) throws -> Double {
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, frame, nil) as? [CFString: Any])
        let gif = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        return try XCTUnwrap((gif[kCGImagePropertyGIFUnclampedDelayTime] ?? gif[kCGImagePropertyGIFDelayTime]) as? Double)
    }

    func testOneFramePerStepOnAConstantCanvas() throws {
        try export(frameSeconds: 2)
        let source = try source()
        XCTAssertEqual(CGImageSourceGetCount(source), 3)
        for index in 0..<3 {
            let frame = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, index, nil))
            // Widest 1200 → capped at 1000; the 800×800 image is the tallest at that width.
            XCTAssertEqual(frame.width, 1000)
            XCTAssertEqual(frame.height, 800 + GIFGuideExporter.captionBandHeight)
        }
    }

    func testFrameDelayAndLoopForever() throws {
        try export(frameSeconds: 2)
        let source = try source()
        for index in 0..<3 { XCTAssertEqual(try delay(of: index, in: source), 2, accuracy: 0.01) }
        let properties = try XCTUnwrap(CGImageSourceCopyProperties(source, nil) as? [CFString: Any])
        let gif = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
        XCTAssertEqual(gif[kCGImagePropertyGIFLoopCount] as? Int, 0)
    }

    func testFrameTimeIsClampedToOneToFiveSeconds() throws {
        try export(frameSeconds: 9)
        XCTAssertEqual(try delay(of: 0, in: source()), 5, accuracy: 0.01)
        try export(frameSeconds: 0.2)
        XCTAssertEqual(try delay(of: 0, in: source()), 1, accuracy: 0.01)
    }

    func testCanvasSizeLimits() throws {
        XCTAssertEqual(GIFGuideExporter.canvasSize(for: [nil]),
                       CGSize(width: 1000, height: GIFGuideExporter.placeholderHeight + GIFGuideExporter.captionBandHeight))
        XCTAssertEqual(GIFGuideExporter.canvasSize(for: [try solid(width: 300, height: 100)]),
                       CGSize(width: 480, height: 100 + GIFGuideExporter.captionBandHeight))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipprTests.GIFGuideExporterTests`
Expected: build fails with `error: cannot find 'GIFGuideExporter' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Clipr/AdvancedMode/Export/GIFGuideExporter.swift`:

```swift
// Sources/Clipr/AdvancedMode/Export/GIFGuideExporter.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// An animated slideshow of the guide for chat and READMEs: one frame per step, the step image
/// centred on a fixed canvas with its caption in a band underneath, looping forever.
enum GIFGuideExporter {
    static let maxCanvasWidth = 1000
    /// Keeps the caption band readable when every step is a small crop.
    static let minCanvasWidth = 480
    static let captionBandHeight = 72
    /// Image-area height when no step has an image at all.
    static let placeholderHeight = 400

    enum GIFError: Error { case cannotCreate, encodeFailed }

    static func clampedFrameSeconds(_ seconds: Double) -> Double {
        min(max(seconds, ExportOptions.gifFrameRange.lowerBound), ExportOptions.gifFrameRange.upperBound)
    }

    /// One canvas for every frame, so the GIF doesn't jump: as wide as the widest image (within
    /// limits) and as tall as the tallest image at that width, plus the caption band.
    static func canvasSize(for images: [GuideImage?]) -> CGSize {
        let present = images.compactMap { $0 }
        let widest = present.map(\.pixelWidth).max() ?? maxCanvasWidth
        let width = min(maxCanvasWidth, max(minCanvasWidth, widest))
        let tallest = present.map { fittedSize($0, width: width).height }.max() ?? placeholderHeight
        return CGSize(width: width, height: tallest + captionBandHeight)
    }

    /// `image` scaled down (never up) to fit `width`.
    static func fittedSize(_ image: GuideImage, width: Int) -> (width: Int, height: Int) {
        guard image.pixelWidth > width else { return (image.pixelWidth, image.pixelHeight) }
        return (width, max(1, Int((Double(image.pixelHeight) * Double(width) / Double(image.pixelWidth)).rounded())))
    }

    static func export(_ doc: GuideDocument, images: RenderedImages, frameSeconds: Double, to url: URL) throws {
        let frames = doc.steps.map { images.steps[$0.number] }
        let canvas = canvasSize(for: frames)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, doc.steps.count, nil) else {
            throw GIFError.cannotCreate
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let delay = clampedFrameSeconds(frameSeconds)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay],
        ] as CFDictionary
        for (step, image) in zip(doc.steps, frames) {
            let caption = CaptionMarkup.plainText(step.caption, fallbackNumber: step.number)
            guard let frame = renderFrame(image, caption: caption, canvas: canvas) else { throw GIFError.encodeFailed }
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { throw GIFError.encodeFailed }
    }

    static func renderFrame(_ image: GuideImage?, caption: String, canvas: CGSize) -> CGImage? {
        let width = Int(canvas.width)
        guard let context = CGContext(
            data: nil, width: width, height: Int(canvas.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        let band = CGFloat(captionBandHeight)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: canvas))
        // CG is y-up: the caption band is at the bottom, so the image area starts above it.
        let imageArea = CGRect(x: 0, y: band, width: canvas.width, height: canvas.height - band)
        if let image, let source = CGImageSourceCreateWithData(image.data as CFData, nil),
           let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let fitted = fittedSize(image, width: width)
            context.interpolationQuality = .high
            context.draw(decoded, in: CGRect(
                x: (canvas.width - CGFloat(fitted.width)) / 2,
                y: imageArea.minY + (imageArea.height - CGFloat(fitted.height)) / 2,
                width: CGFloat(fitted.width), height: CGFloat(fitted.height)
            ))
        } else {
            let box = imageArea.insetBy(dx: 24, dy: 24)
            context.setFillColor(CGColor(gray: 0.95, alpha: 1))
            context.fill(box)
            drawText("Image unavailable", in: box, size: 18, color: NSColor(white: 0.55, alpha: 1), context: context)
        }
        context.setFillColor(CGColor(gray: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvas.width, height: band))
        drawText(caption, in: CGRect(x: 16, y: 0, width: canvas.width - 32, height: band), size: 20,
                 color: NSColor(white: 0.11, alpha: 1), context: context)
        return context.makeImage()
    }

    /// One centred line, truncated with "…" if it doesn't fit.
    private static func drawText(_ text: String, in rect: CGRect, size: CGFloat, color: NSColor, context: CGContext) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])
        let lineHeight = ceil(attributed.size().height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attributed.draw(with: CGRect(x: rect.minX, y: rect.midY - lineHeight / 2, width: rect.width, height: lineHeight),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        NSGraphicsContext.restoreGraphicsState()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClipprTests.GIFGuideExporterTests`
Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/Export/GIFGuideExporter.swift Tests/ClipprTests/GIFGuideExporterTests.swift
git commit -m "feat: animated GIF guide export" -m "Claude-Session: https://claude.ai/code/session_01J9DeGERVvr6uhbMe87JjkA"
```

---

### Task 7: PDFGuideExporter

**Files:**
- Create: `Sources/Clipr/AdvancedMode/Export/PDFGuideExporter.swift`
- Test: `Tests/ClipprTests/PDFGuideExporterTests.swift`

**Interfaces:**
- Consumes: Task 3 `HTMLGuideWriter.write(_:images:mode: .embedded)` (tests; production callers pass its output); Task 5 `GuideImages.encode(_:)` (tests).
- Produces:
  - `enum PDFExportError: Error, Equatable { case loadFailed, timedOut, printFailed }`
  - `@MainActor final class PDFGuideExporter: NSObject, WKNavigationDelegate { nonisolated static let defaultTimeout: TimeInterval = 30; nonisolated static let marginPoints: CGFloat; init(timeout: TimeInterval = PDFGuideExporter.defaultTimeout); static func paperSize(for locale: Locale) -> NSSize; func export(html: String, to url: URL, locale: Locale = .current) async throws }` — one export per instance.

**Main-thread requirements:** `WKWebView`, `NSPrintOperation` and `NSWindow` must be created and driven on the main thread; the class is `@MainActor`. Navigation and print-completion callbacks arrive through the main run loop, so the caller must *suspend* (await), never block the main thread. In tests: the test class is `@MainActor`, the export runs in a `Task`, and the test awaits `fulfillment(of:timeout:)` on an `XCTestExpectation` — that suspends without blocking the run loop, and its 60 s timeout stops a hung export from hanging `swift test` (there is no `timeout` binary on macOS). `swift test` doesn't create `NSApplication`, so `setUp` touches `NSApplication.shared` first.

- [ ] **Step 1: Write the failing test**

Create `Tests/ClipprTests/PDFGuideExporterTests.swift`:

```swift
// Tests/ClipprTests/PDFGuideExporterTests.swift
import XCTest
import Cocoa
import PDFKit
@testable import Clipr

/// WebKit printing runs on the main thread and calls back through the main run loop. The tests
/// are main-actor async: awaiting an XCTest expectation suspends the test without blocking the
/// main thread, so those callbacks get to run, and the expectation's timeout stops a hung export
/// failing the whole run (macOS has no `timeout` command to wrap `swift test` in).
@MainActor
final class PDFGuideExporterTests: XCTestCase {
    var folder: URL!

    override func setUp() async throws {
        // AppKit printing expects the shared application to exist; `swift test` doesn't create it.
        _ = NSApplication.shared
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func guideHTML(steps count: Int) throws -> String {
        let picture = testImage(width: 400, height: 225) {
            NSColor.systemTeal.set()
            NSRect(x: 0, y: 0, width: 400, height: 225).fill()
        }
        let image = try XCTUnwrap(GuideImages.encode(try XCTUnwrap(picture.bitmap)))
        let steps = (1...count).map {
            GuideStep(number: $0, caption: "Heading \($0) end", appName: "Safari", imageSize: .full,
                      image: .file(URL(fileURLWithPath: "/unused.png")), zoom: nil)
        }
        var images = RenderedImages()
        for step in steps { images.steps[step.number] = image }
        return HTMLGuideWriter.write(GuideDocument(title: "PDF test", date: Date(), steps: steps), images: images, mode: .embedded)
    }

    /// Runs one export and waits for it with an expectation, returning the file and any error.
    private func export(_ html: String, timeout: TimeInterval = PDFGuideExporter.defaultTimeout) async -> (URL, Error?) {
        let url = folder.appendingPathComponent("guide.pdf")
        let exporter = PDFGuideExporter(timeout: timeout)
        let done = expectation(description: "PDF export finished")
        let task = Task { @MainActor () -> Error? in
            defer { done.fulfill() }
            do {
                try await exporter.export(html: html, to: url)
                return nil
            } catch {
                return error
            }
        }
        await fulfillment(of: [done], timeout: 60)
        return (url, await task.value)
    }

    func testThreeStepsMakeAPDFWithEveryHeading() async throws {
        let (url, error) = await export(try guideHTML(steps: 3))
        XCTAssertNil(error)
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 1)
        let text = try XCTUnwrap(pdf.string)
        for number in 1...3 { XCTAssertTrue(text.contains("Heading \(number) end"), "step \(number)") }
    }

    func testThirtyStepsPaginate() async throws {
        let (url, error) = await export(try guideHTML(steps: 30))
        XCTAssertNil(error)
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        let text = try XCTUnwrap(pdf.string)
        for number in 1...30 { XCTAssertTrue(text.contains("Heading \(number) end"), "step \(number)") }
    }

    func testTimeoutReportsTimedOut() async throws {
        let (_, error) = await export(try guideHTML(steps: 3), timeout: 0.001)
        XCTAssertEqual(error as? PDFExportError, .timedOut)
    }

    func testPaperSizeFollowsLocale() {
        XCTAssertEqual(PDFGuideExporter.paperSize(for: Locale(identifier: "en_US")), NSSize(width: 612, height: 792))
        XCTAssertEqual(PDFGuideExporter.paperSize(for: Locale(identifier: "en_GB")), NSSize(width: 595.28, height: 841.89))
        XCTAssertEqual(PDFGuideExporter.paperSize(for: Locale(identifier: "de_DE")), NSSize(width: 595.28, height: 841.89))
        XCTAssertEqual(PDFGuideExporter.marginPoints, 51.02, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipprTests.PDFGuideExporterTests`
Expected: build fails with `error: cannot find 'PDFGuideExporter' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Clipr/AdvancedMode/Export/PDFGuideExporter.swift`:

```swift
// Sources/Clipr/AdvancedMode/Export/PDFGuideExporter.swift
import AppKit
import WebKit

enum PDFExportError: Error, Equatable {
    case loadFailed
    case timedOut
    case printFailed
}

/// Prints the guide's embedded HTML through WebKit straight to a PDF file, so pagination follows
/// the template's `break-inside: avoid` and the PDF matches the HTML export exactly.
///
/// Main thread only (WebKit and AppKit printing). One export per instance. The web view lives in
/// a borderless window that is never shown: `NSPrintOperation.runModal(for:…)` needs a window to
/// run for, and a web view's print operation run without one prints blank pages.
@MainActor
final class PDFGuideExporter: NSObject, WKNavigationDelegate {
    nonisolated static let defaultTimeout: TimeInterval = 30
    /// 18 mm in points.
    nonisolated static let marginPoints: CGFloat = 18 / 25.4 * 72
    /// Regions that use US Letter; everywhere else gets A4.
    private static let letterRegions: Set<String> = ["US", "CA", "MX", "PH", "PR", "CL", "CO", "VE", "GT", "CR"]

    private let timeout: TimeInterval
    private var webView: WKWebView?
    private var window: NSWindow?
    private var destination: URL?
    private var paperSize = NSSize(width: 595.28, height: 841.89)
    private var continuation: CheckedContinuation<Void, Error>?

    init(timeout: TimeInterval = PDFGuideExporter.defaultTimeout) {
        self.timeout = timeout
    }

    static func paperSize(for locale: Locale) -> NSSize {
        letterRegions.contains(locale.region?.identifier ?? "")
            ? NSSize(width: 612, height: 792)
            : NSSize(width: 595.28, height: 841.89)
    }

    /// Throws `PDFExportError`. Gives up with `.timedOut` after `timeout` seconds.
    func export(html: String, to url: URL, locale: Locale = .current) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            destination = url
            paperSize = Self.paperSize(for: locale)
            let frame = NSRect(x: 0, y: 0, width: 800, height: 1000)
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let webView = WKWebView(frame: frame)
            window.contentView = webView
            webView.navigationDelegate = self
            self.window = window
            self.webView = webView
            webView.loadHTMLString(html, baseURL: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.failure(PDFExportError.timedOut))
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        startPrinting()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(PDFExportError.loadFailed))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(PDFExportError.loadFailed))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(PDFExportError.loadFailed))
    }

    private func startPrinting() {
        guard let webView, let window, let destination, continuation != nil else { return }
        let info = NSPrintInfo()
        info.paperSize = paperSize
        info.topMargin = Self.marginPoints
        info.bottomMargin = Self.marginPoints
        info.leftMargin = Self.marginPoints
        info.rightMargin = Self.marginPoints
        info.horizontalPagination = .automatic
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = destination
        let operation = webView.printOperation(with: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        // The operation's view starts zero-sized; without a frame WebKit lays out nothing to print.
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: self,
                           didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let written = destination.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        finish(success && written ? .success(()) : .failure(PDFExportError.printFailed))
    }

    /// Resumes the caller exactly once, whichever of success, failure or the timeout comes first.
    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        webView?.navigationDelegate = nil
        webView = nil
        window = nil
        continuation.resume(with: result)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClipprTests.PDFGuideExporterTests`
Expected: `Executed 4 tests, with 0 failures` in well under a second each (the prototype printed 30 steps in ~0.2 s). If the PDF tests fail with a page count of 0 or missing headings, check that `operation.view?.frame` is set and that `runModal(for:…)` (not `run()`) is used — both are required for WebKit to lay out the printed pages.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/Export/PDFGuideExporter.swift Tests/ClipprTests/PDFGuideExporterTests.swift
git commit -m "feat: PDF guide export by printing the HTML through WebKit" -m "Claude-Session: https://claude.ai/code/session_01J9DeGERVvr6uhbMe87JjkA"
```

---

### Task 8: GuideClipboard

**Files:**
- Create: `Sources/Clipr/AdvancedMode/Export/GuideClipboard.swift`
- Test: `Tests/ClipprTests/GuideClipboardTests.swift`

**Interfaces:**
- Consumes: Task 3 `HTMLGuideWriter.write(_:images:mode:)` (tests); Task 1 spike outcome line in `docs/superpowers/checklists/advanced-mode-capture-manual.md`.
- Produces:
  - `enum GuideClipboard { static let imagesMayBeDropped: Bool; static let webAppNote = "Images may not paste into some web apps — use PDF or Markdown"; @MainActor @discardableResult static func write(html: String, to pasteboard: NSPasteboard = .general) -> Bool; @MainActor static func rtfData(fromHTML html: String) -> Data? }`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClipprTests/GuideClipboardTests.swift`:

```swift
// Tests/ClipprTests/GuideClipboardTests.swift
import XCTest
import Cocoa
@testable import Clipr

@MainActor
final class GuideClipboardTests: XCTestCase {
    var pasteboard: NSPasteboard!

    override func setUp() async throws {
        // A private pasteboard, so the tests never touch what the user has copied.
        pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipprTests.\(UUID().uuidString)"))
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    private var html: String {
        let doc = GuideDocument(title: "Clip test", date: Date(), steps: [
            GuideStep(number: 1, caption: "Click **Save** now", appName: "Safari", imageSize: .full, image: .missing, zoom: nil),
        ])
        return HTMLGuideWriter.write(doc, images: RenderedImages(), mode: .embedded)
    }

    func testWritesHTMLAndRTF() throws {
        XCTAssertTrue(GuideClipboard.write(html: html, to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .html), html)
        let rtf = try XCTUnwrap(pasteboard.data(forType: .rtf))
        let text = try XCTUnwrap(NSAttributedString(rtf: rtf, documentAttributes: nil))
        XCTAssertTrue(text.string.contains("Clip test"))
        XCTAssertTrue(text.string.contains("Click Save now"))
    }

    func testRTFKeepsBold() throws {
        let rtf = try XCTUnwrap(GuideClipboard.rtfData(fromHTML: html))
        let text = try XCTUnwrap(NSAttributedString(rtf: rtf, documentAttributes: nil))
        let range = (text.string as NSString).range(of: "Save")
        XCTAssertNotEqual(range.location, NSNotFound)
        let font = try XCTUnwrap(text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testReplacesWhatWasOnThePasteboard() {
        pasteboard.clearContents()
        pasteboard.setString("old", forType: .string)
        GuideClipboard.write(html: html, to: pasteboard)
        // The pasteboard may derive plain text from the RTF, but the old string must be gone.
        XCTAssertNotEqual(pasteboard.string(forType: .string), "old")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipprTests.GuideClipboardTests`
Expected: build fails with `error: cannot find 'GuideClipboard' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Clipr/AdvancedMode/Export/GuideClipboard.swift`. Set `imagesMayBeDropped` from the `Outcome:` line recorded in Task 1 Step 1 — the code below shows `true`; change it to `false` only if the recorded outcome is `imagesMayBeDropped = false`:

```swift
// Sources/Clipr/AdvancedMode/Export/GuideClipboard.swift
import AppKit

/// Puts the guide on the pasteboard as HTML (what web docs tools read) and RTF (what Pages, Word
/// and TextEdit read), both from the same embedded HTML the HTML export writes.
enum GuideClipboard {
    /// From the clipboard spike recorded in `docs/superpowers/checklists/advanced-mode-capture-manual.md`
    /// ("Export — clipboard spike"): true when any web docs tool dropped the pasted images.
    static let imagesMayBeDropped = true
    static let webAppNote = "Images may not paste into some web apps — use PDF or Markdown"

    /// Main thread only: AppKit's HTML import runs on WebKit. False if the pasteboard refused the HTML.
    @MainActor
    @discardableResult
    static func write(html: String, to pasteboard: NSPasteboard = .general) -> Bool {
        let rtf = rtfData(fromHTML: html)
        pasteboard.clearContents()
        var written = pasteboard.setString(html, forType: .html)
        if let rtf { written = pasteboard.setData(rtf, forType: .rtf) && written }
        return written
    }

    @MainActor
    static func rtfData(fromHTML html: String) -> Data? {
        guard let attributed = NSAttributedString(
            html: Data(html.utf8),
            options: [.characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        ) else { return nil }
        return attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClipprTests.GuideClipboardTests`
Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/Export/GuideClipboard.swift Tests/ClipprTests/GuideClipboardTests.swift
git commit -m "feat: copy the guide to the clipboard as HTML and RTF" -m "Claude-Session: https://claude.ai/code/session_01J9DeGERVvr6uhbMe87JjkA"
```

---

### Task 9: GuideExporter (progress, cancel, work folder then move)

**Files:**
- Create: `Sources/Clipr/AdvancedMode/Export/GuideExporter.swift`
- Test: `Tests/ClipprTests/GuideExporterTests.swift`

**Interfaces:**
- Consumes: Task 1 `GuideDocument`, `GuideFormat`, `ExportOptions`, `RenderedImages`, `GuideImageRef`; Task 3 `HTMLGuideWriter.write`; Task 4 `MarkdownGuideWriter.export`, `.fileName`, `.imagesFolder`; Task 5 `GuideImages.render`, `.maxPixelWidth(for:)`, `.zoomPixelWidth`, `GuideImageRender`; Task 6 `GIFGuideExporter.export`, `.maxCanvasWidth`; Task 7 `PDFGuideExporter().export(html:to:)`; Task 8 `GuideClipboard.write(html:)`.
- Produces:
  - `enum GuideWarning: Equatable { case missingImage(step: Int), damagedAnnotations(step: Int); static func summary(_ warnings: [GuideWarning]) -> String? }`
  - `enum GuideExportError: LocalizedError, Equatable { case cancelled, destinationNotWritable(String), writeFailed(String), pdfFailed, clipboardFailed }` (`pdfFailed.errorDescription` = "Couldn't create the PDF. Try exporting as HTML instead.")
  - `final class CancelFlag: @unchecked Sendable { var isSet: Bool; func set() }`
  - `@MainActor struct GuideExporter { var renderImage: @Sendable (GuideImageRef, Int) -> GuideImageRender; var writePDF: @MainActor (String, URL) async throws -> Void; var copyToClipboard: @MainActor (String) -> Bool; var workRoot: URL? = nil; func export(_ doc: GuideDocument, options: ExportOptions, to destination: URL?, isCancelled: @escaping @Sendable () -> Bool = { false }, progress: @escaping @MainActor (Double) -> Void = { _ in }) async throws -> [GuideWarning]; nonisolated static func renderImages(_:format:render:isCancelled:progress:) throws -> (RenderedImages, [GuideWarning]); nonisolated static func moveIntoPlace(_ output: URL, format: GuideFormat, destination: URL) throws }`
  - Destination contract: PDF/HTML/GIF → the file URL from the save panel; Markdown → the chosen folder (receives `guide.md` + `images/`); clipboard → `nil`.
  - Cancellation: cancelling the Swift `Task` that awaits `export` (or `isCancelled` returning true) stops before the next step with `GuideExportError.cancelled`.

- [ ] **Step 1: Write the failing test**

Create `Tests/ClipprTests/GuideExporterTests.swift`:

```swift
// Tests/ClipprTests/GuideExporterTests.swift
import XCTest
import Cocoa
@testable import Clipr

@MainActor
final class GuideExporterTests: XCTestCase {
    var root: URL!
    var work: URL!
    var out: URL!

    /// Counts render calls from the background render loop; read only after the export returns.
    final class Calls: @unchecked Sendable {
        var widths: [Int] = []
    }

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        work = root.appendingPathComponent("work")
        out = root.appendingPathComponent("out")
        for folder in [work!, out!] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    }

    override func tearDown() async throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: out.path)
        try? FileManager.default.removeItem(at: root)
    }

    private let png = GuideImage(data: Data([0x89, 0x50, 0x4E, 0x47]), pixelWidth: 10, pixelHeight: 5, kind: .png)

    private func doc(sizes: [ImageSize] = [.small, .full, .full], zoomOnFirst: Bool = false) -> GuideDocument {
        let somewhere = GuideImageRef.file(URL(fileURLWithPath: "/unused.png"))
        return GuideDocument(title: "T", date: Date(), steps: sizes.enumerated().map { index, size in
            GuideStep(number: index + 1, caption: "Heading \(index + 1)", appName: nil, imageSize: size,
                      image: somewhere, zoom: zoomOnFirst && index == 0 ? somewhere : nil)
        })
    }

    /// Step 2's image is missing and step 3's sidecar is damaged; every other render succeeds.
    private func exporter(calls: Calls = Calls(), pdf: @escaping @MainActor (String, URL) async throws -> Void = { _, url in
        try Data("%PDF".utf8).write(to: url)
    }, clipboard: @escaping @MainActor (String) -> Bool = { _ in true }) -> GuideExporter {
        let image = png
        return GuideExporter(
            renderImage: { _, width in
                calls.widths.append(width)
                switch calls.widths.count {
                case 2: return GuideImageRender(image: nil, sidecarDamaged: false)
                case 3: return GuideImageRender(image: image, sidecarDamaged: true)
                default: return GuideImageRender(image: image, sidecarDamaged: false)
                }
            },
            writePDF: pdf, copyToClipboard: clipboard, workRoot: work
        )
    }

    private func workIsEmpty() throws -> Bool {
        try FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty
    }

    func testHTMLExportWritesFileAndReportsWarnings() async throws {
        let destination = out.appendingPathComponent("Guide.html")
        let warnings = try await exporter().export(doc(), options: ExportOptions(format: .html, title: "T"), to: destination)
        XCTAssertEqual(warnings, [.missingImage(step: 2), .damagedAnnotations(step: 3)])
        let html = try String(contentsOf: destination, encoding: .utf8)
        XCTAssertTrue(html.contains("Image unavailable"))
        XCTAssertTrue(try workIsEmpty())
    }

    func testRequestsWidthPerFormat() async throws {
        let htmlCalls = Calls()
        _ = try await exporter(calls: htmlCalls).export(doc(zoomOnFirst: true), options: ExportOptions(format: .html, title: "T"),
                                                        to: out.appendingPathComponent("a.html"))
        XCTAssertEqual(htmlCalls.widths, [640, 480, 1600, 1600], "step 1, its close-up, steps 2 and 3")
        let gifCalls = Calls()
        _ = try await exporter(calls: gifCalls).export(doc(zoomOnFirst: true), options: ExportOptions(format: .gif, title: "T"),
                                                       to: out.appendingPathComponent("a.gif"))
        XCTAssertEqual(gifCalls.widths, [1000, 1000, 1000], "GIF frames use the canvas width and skip close-ups")
    }

    func testReplacesExistingFileAtDestination() async throws {
        let destination = out.appendingPathComponent("Guide.html")
        try Data("old".utf8).write(to: destination)
        _ = try await exporter().export(doc(), options: ExportOptions(format: .html, title: "T"), to: destination)
        XCTAssertTrue(try String(contentsOf: destination, encoding: .utf8).hasPrefix("<!doctype html>"))
    }

    func testMarkdownReplacesGuideAndImagesInChosenFolder() async throws {
        try Data("old".utf8).write(to: out.appendingPathComponent("guide.md"))
        try FileManager.default.createDirectory(at: out.appendingPathComponent("images"), withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: out.appendingPathComponent("images/stale.png"))
        _ = try await exporter().export(doc(), options: ExportOptions(format: .markdown, title: "T"), to: out)
        XCTAssertTrue(try String(contentsOf: out.appendingPathComponent("guide.md"), encoding: .utf8).hasPrefix("# T\n"))
        let images = try FileManager.default.contentsOfDirectory(atPath: out.appendingPathComponent("images").path).sorted()
        XCTAssertEqual(images, ["step-01.png", "step-03.png"])
        XCTAssertTrue(try workIsEmpty())
    }

    func testCancelStopsBeforeNextStepAndLeavesNothing() async throws {
        let calls = Calls()
        let destination = out.appendingPathComponent("Guide.html")
        do {
            _ = try await exporter(calls: calls).export(doc(), options: ExportOptions(format: .html, title: "T"), to: destination,
                                                        isCancelled: { !calls.widths.isEmpty })
            XCTFail("expected cancellation")
        } catch {
            XCTAssertEqual(error as? GuideExportError, .cancelled)
        }
        XCTAssertEqual(calls.widths.count, 1, "stopped before the second step")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try workIsEmpty())
    }

    func testCancellingTheTaskCancelsTheExport() async throws {
        let destination = out.appendingPathComponent("Guide.html")
        let exporter = exporter()
        let task = Task { @MainActor in
            try await exporter.export(doc(), options: ExportOptions(format: .html, title: "T"), to: destination)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch {
            XCTAssertEqual(error as? GuideExportError, .cancelled)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testUnwritableDestinationLeavesNothing() async throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: out.path)
        let destination = out.appendingPathComponent("Guide.html")
        do {
            _ = try await exporter().export(doc(), options: ExportOptions(format: .html, title: "T"), to: destination)
            XCTFail("expected a failure")
        } catch {
            guard case .destinationNotWritable = error as? GuideExportError else { return XCTFail("\(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try workIsEmpty())
    }

    func testPDFFailureSuggestsHTMLAndLeavesNothing() async throws {
        struct Boom: Error {}
        let destination = out.appendingPathComponent("Guide.pdf")
        do {
            _ = try await exporter(pdf: { _, _ in throw Boom() }).export(doc(), options: ExportOptions(format: .pdf, title: "T"), to: destination)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? GuideExportError, .pdfFailed)
            XCTAssertEqual(error.localizedDescription, "Couldn't create the PDF. Try exporting as HTML instead.")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertTrue(try workIsEmpty())
    }

    func testClipboardGetsEmbeddedHTMLAndNeedsNoDestination() async throws {
        var copied: String?
        let warnings = try await exporter(clipboard: { copied = $0; return true })
            .export(doc(), options: ExportOptions(format: .clipboard, title: "T"), to: nil)
        XCTAssertEqual(warnings.count, 2)
        XCTAssertTrue(try XCTUnwrap(copied).contains("data:image/png;base64,"))
    }

    func testRenderProgressReachesOne() throws {
        var fractions: [Double] = []
        _ = try GuideExporter.renderImages(doc(), format: .html, render: { _, _ in GuideImageRender(image: nil, sidecarDamaged: false) },
                                           isCancelled: { false }, progress: { fractions.append($0) })
        XCTAssertEqual(fractions, [1.0 / 3, 2.0 / 3, 1])
    }

    func testWarningSummary() {
        XCTAssertNil(GuideWarning.summary([]))
        XCTAssertEqual(GuideWarning.summary([.missingImage(step: 2), .missingImage(step: 5), .damagedAnnotations(step: 3)]),
                       "Steps 2, 5: image unavailable — exported with a placeholder.\nStep 3: annotations couldn't be read — exported without them.")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ClipprTests.GuideExporterTests`
Expected: build fails with `error: cannot find 'GuideExporter' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/Clipr/AdvancedMode/Export/GuideExporter.swift`:

```swift
// Sources/Clipr/AdvancedMode/Export/GuideExporter.swift
import AppKit

/// Something that went wrong with one step but didn't stop the export.
enum GuideWarning: Equatable {
    case missingImage(step: Int)
    case damagedAnnotations(step: Int)

    /// The alert text listing affected steps, or nil when there's nothing to report.
    static func summary(_ warnings: [GuideWarning]) -> String? {
        let missing = warnings.compactMap { if case .missingImage(let step) = $0 { return step } else { return nil } }
        let damaged = warnings.compactMap { if case .damagedAnnotations(let step) = $0 { return step } else { return nil } }
        var lines: [String] = []
        if !missing.isEmpty { lines.append("\(stepList(missing)): image unavailable — exported with a placeholder.") }
        if !damaged.isEmpty { lines.append("\(stepList(damaged)): annotations couldn't be read — exported without them.") }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func stepList(_ steps: [Int]) -> String {
        (steps.count == 1 ? "Step " : "Steps ") + steps.map(String.init).joined(separator: ", ")
    }
}

enum GuideExportError: LocalizedError, Equatable {
    case cancelled
    case destinationNotWritable(String)
    case writeFailed(String)
    case pdfFailed
    case clipboardFailed

    var errorDescription: String? {
        switch self {
        case .cancelled: return "Export cancelled."
        case .destinationNotWritable(let reason): return "Couldn't write to the chosen location. \(reason)"
        case .writeFailed(let reason): return "Couldn't finish the export. \(reason)"
        case .pdfFailed: return "Couldn't create the PDF. Try exporting as HTML instead."
        case .clipboardFailed: return "Couldn't copy the guide to the clipboard."
        }
    }
}

/// Set from the main actor when the user cancels, read by the background render loop.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// Runs one export: renders step images off the main thread (reporting progress per step and
/// stopping before the next step once cancelled), writes the output into a work folder, and only
/// then moves it to the destination — so a failed or cancelled export never leaves a half-written
/// file where the user asked for one. The work folder is always removed.
@MainActor
struct GuideExporter {
    var renderImage: @Sendable (GuideImageRef, Int) -> GuideImageRender = { GuideImages.render($0, maxPixelWidth: $1) }
    var writePDF: @MainActor (String, URL) async throws -> Void = { html, url in
        try await PDFGuideExporter().export(html: html, to: url)
    }
    var copyToClipboard: @MainActor (String) -> Bool = { GuideClipboard.write(html: $0) }
    /// Where work folders are made. Nil: the system's temporary folder on the destination's volume,
    /// so the final move is a rename.
    var workRoot: URL? = nil

    /// Returns the warnings to show. Throws `GuideExportError`. Cancelling the calling task, or
    /// `isCancelled` returning true, stops the export with `.cancelled`.
    func export(
        _ doc: GuideDocument,
        options: ExportOptions,
        to destination: URL?,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        progress: @escaping @MainActor (Double) -> Void = { _ in }
    ) async throws -> [GuideWarning] {
        let flag = CancelFlag()
        let cancelled: @Sendable () -> Bool = { flag.isSet || isCancelled() }
        return try await withTaskCancellationHandler {
            try await run(doc, options: options, destination: destination, isCancelled: cancelled, progress: progress)
        } onCancel: {
            flag.set()
        }
    }

    private func run(
        _ doc: GuideDocument, options: ExportOptions, destination: URL?,
        isCancelled: @escaping @Sendable () -> Bool, progress: @escaping @MainActor (Double) -> Void
    ) async throws -> [GuideWarning] {
        let format = options.format
        let render = renderImage
        let (images, warnings) = try await Task.detached(priority: .userInitiated) {
            try Self.renderImages(doc, format: format, render: render, isCancelled: isCancelled) { fraction in
                DispatchQueue.main.async { progress(fraction) }
            }
        }.value

        if format == .clipboard {
            guard copyToClipboard(HTMLGuideWriter.write(doc, images: images, mode: .embedded)) else {
                throw GuideExportError.clipboardFailed
            }
            return warnings
        }
        guard let destination else { throw GuideExportError.writeFailed("No destination was chosen.") }

        let work: URL
        do {
            work = try makeWorkFolder(for: destination)
        } catch {
            throw GuideExportError.destinationNotWritable(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: work) }

        // Markdown is assembled in a folder whose contents (guide.md, images/) are moved across.
        let output = work.appendingPathComponent(format == .markdown ? "Guide" : destination.lastPathComponent)
        if format == .pdf {
            do {
                try await writePDF(HTMLGuideWriter.write(doc, images: images, mode: .embedded), output)
            } catch {
                throw GuideExportError.pdfFailed
            }
        } else {
            let frameSeconds = options.gifFrameSeconds
            try await Task.detached(priority: .userInitiated) {
                do {
                    try Self.writeFile(doc, images: images, format: format, frameSeconds: frameSeconds, to: output)
                } catch {
                    throw GuideExportError.writeFailed(error.localizedDescription)
                }
            }.value
        }
        if isCancelled() { throw GuideExportError.cancelled }
        do {
            try Self.moveIntoPlace(output, format: format, destination: destination)
        } catch {
            throw GuideExportError.destinationNotWritable(error.localizedDescription)
        }
        return warnings
    }

    /// Each step's image at the width its format needs, plus the warnings for steps whose image is
    /// missing or whose annotations couldn't be read. GIF frames use the canvas width and skip close-ups.
    nonisolated static func renderImages(
        _ doc: GuideDocument, format: GuideFormat,
        render: (GuideImageRef, Int) -> GuideImageRender,
        isCancelled: () -> Bool, progress: (Double) -> Void
    ) throws -> (RenderedImages, [GuideWarning]) {
        var images = RenderedImages()
        var warnings: [GuideWarning] = []
        for (index, step) in doc.steps.enumerated() {
            if isCancelled() { throw GuideExportError.cancelled }
            let width = format == .gif ? GIFGuideExporter.maxCanvasWidth : GuideImages.maxPixelWidth(for: step.imageSize)
            let main = render(step.image, width)
            if let image = main.image {
                images.steps[step.number] = image
            } else {
                warnings.append(.missingImage(step: step.number))
            }
            if main.sidecarDamaged { warnings.append(.damagedAnnotations(step: step.number)) }
            if format != .gif, let zoom = step.zoom, let image = render(zoom, GuideImages.zoomPixelWidth).image {
                images.zooms[step.number] = image
            }
            progress(Double(index + 1) / Double(doc.steps.count))
        }
        if isCancelled() { throw GuideExportError.cancelled }
        return (images, warnings)
    }

    nonisolated private static func writeFile(_ doc: GuideDocument, images: RenderedImages, format: GuideFormat,
                                              frameSeconds: Double, to output: URL) throws {
        switch format {
        case .html: try Data(HTMLGuideWriter.write(doc, images: images, mode: .embedded).utf8).write(to: output)
        case .markdown: try MarkdownGuideWriter.export(doc, images: images, to: output)
        case .gif: try GIFGuideExporter.export(doc, images: images, frameSeconds: frameSeconds, to: output)
        case .pdf, .clipboard: break
        }
    }

    private func makeWorkFolder(for destination: URL) throws -> URL {
        let fileManager = FileManager.default
        guard let workRoot else {
            return try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                       appropriateFor: destination, create: true)
        }
        let folder = workRoot.appendingPathComponent("ClipprExport-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Replaces what's at the destination only now that the output is complete. For Markdown the
    /// destination is the chosen folder: `images/` moves first, so a failure never leaves a new
    /// guide.md pointing at images that aren't there.
    nonisolated static func moveIntoPlace(_ output: URL, format: GuideFormat, destination: URL) throws {
        if format == .markdown {
            for name in [MarkdownGuideWriter.imagesFolder, MarkdownGuideWriter.fileName] {
                try place(output.appendingPathComponent(name), at: destination.appendingPathComponent(name))
            }
        } else {
            try place(output, at: destination)
        }
    }

    nonisolated private static func place(_ item: URL, at target: URL) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: item)
        } else {
            try FileManager.default.moveItem(at: item, to: target)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ClipprTests.GuideExporterTests`
Expected: `Executed 11 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Clipr/AdvancedMode/Export/GuideExporter.swift Tests/ClipprTests/GuideExporterTests.swift
git commit -m "feat: export coordinator with progress, cancel and all-or-nothing output" -m "Claude-Session: https://claude.ai/code/session_01J9DeGERVvr6uhbMe87JjkA"
```

---

### Task 10: Remembered export options and the sheet model

**Files:**
- Modify: `Sources/Clipr/Settings/SettingsStore.swift` (`Key` enum; new methods above `private func decoded`)
- Create: `Sources/Clipr/AdvancedMode/Export/ExportSheetModel.swift`
- Test: `Tests/ClipprTests/SettingsStoreTests.swift` (modify), `Tests/ClipprTests/ExportSheetModelTests.swift` (create)

**Interfaces:**
- Consumes: Task 1 `ExportOptions`, `GuideFormat`, `GuideDocument.make`; Task 6 `GIFGuideExporter.clampedFrameSeconds(_:)`; Task 8 `GuideClipboard.imagesMayBeDropped`; existing `SettingsStore(defaults:)`.
- Produces:
  - `SettingsStore.exportOptions(title: String) -> ExportOptions`; `SettingsStore.rememberExportOptions(_ options: ExportOptions)` (UserDefaults keys `exportFormat`, `exportIncludeZoom`, `exportGIFFrameSeconds`)
  - `@MainActor final class ExportSheetModel: ObservableObject { @Published var options: ExportOptions; @Published var useSelection: Bool; let selectionCount: Int; let totalCount: Int; init(manifest: SessionManifest, folder: URL, selection: Set<UUID>, settings: SettingsStore); var stepCount: Int; var canExport: Bool; var actionTitle: String; var showsWebAppNote: Bool; func makeDocument() -> GuideDocument; func rememberOptions() }`

- [ ] **Step 1: Write the failing tests**

In `Tests/ClipprTests/SettingsStoreTests.swift`, insert after `testUnknownReviewLayoutFallsBackToList()`:

```swift
    func testExportOptionsDefaultAndPersist() {
        XCTAssertEqual(store.exportOptions(title: "T"), ExportOptions(format: .pdf, title: "T", includeZoom: false, gifFrameSeconds: 2))
        store.rememberExportOptions(ExportOptions(format: .markdown, title: "Ignored", includeZoom: true, gifFrameSeconds: 4))
        XCTAssertEqual(SettingsStore(defaults: defaults).exportOptions(title: "New"),
                       ExportOptions(format: .markdown, title: "New", includeZoom: true, gifFrameSeconds: 4))
    }

    func testExportOptionsToleratesUnknownFormatAndOutOfRangeFrameTime() {
        defaults.set("pptx", forKey: "exportFormat")
        defaults.set(12.0, forKey: "exportGIFFrameSeconds")
        let options = store.exportOptions(title: "T")
        XCTAssertEqual(options.format, .pdf)
        XCTAssertEqual(options.gifFrameSeconds, 5)
    }
```

Create `Tests/ClipprTests/ExportSheetModelTests.swift`:

```swift
// Tests/ClipprTests/ExportSheetModelTests.swift
import XCTest
@testable import Clipr

@MainActor
final class ExportSheetModelTests: XCTestCase {
    var defaults: UserDefaults!
    var settings: SettingsStore!
    var folder: URL!
    var manifest: SessionManifest!

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: "ClipprTests.\(UUID().uuidString)")
        settings = SettingsStore(defaults: defaults)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Session_2026-10-04_09-30-00")
        let steps = (1...3).map { index in
            StepRecord(id: UUID(), file: String(format: "Step_%02d.png", index), kind: .click, caption: "Step \(index)",
                       clickPoint: nil, zoomFile: nil, appName: nil, capturedAt: Date(timeIntervalSince1970: 0))
        }
        manifest = SessionManifest(createdAt: Date(timeIntervalSince1970: 0), steps: steps)
    }

    private func model(selection: Set<UUID> = []) -> ExportSheetModel {
        ExportSheetModel(manifest: manifest, folder: folder, selection: selection, settings: settings)
    }

    func testDefaultsWithoutSelection() {
        let model = model()
        XCTAssertEqual(model.options, ExportOptions(format: .pdf, title: "Session_2026-10-04_09-30-00", includeZoom: false, gifFrameSeconds: 2))
        XCTAssertEqual(model.selectionCount, 0)
        XCTAssertFalse(model.useSelection)
        XCTAssertEqual(model.stepCount, 3)
        XCTAssertTrue(model.canExport)
        XCTAssertEqual(model.makeDocument().steps.count, 3)
    }

    func testSelectionIsOfferedAndUsedByDefault() {
        let model = model(selection: [manifest.steps[2].id, UUID()])
        XCTAssertEqual(model.selectionCount, 1, "ids no longer in the session don't count")
        XCTAssertTrue(model.useSelection)
        XCTAssertEqual(model.makeDocument().steps.map(\.caption), ["Step 3"])
        model.useSelection = false
        XCTAssertEqual(model.stepCount, 3)
        XCTAssertEqual(model.makeDocument().steps.count, 3)
    }

    func testRemembersOptionsButNotTitle() {
        let first = model()
        first.options.format = .gif
        first.options.includeZoom = true
        first.options.gifFrameSeconds = 3.5
        first.options.title = "Custom"
        first.rememberOptions()
        XCTAssertEqual(model().options, ExportOptions(format: .gif, title: "Session_2026-10-04_09-30-00", includeZoom: true, gifFrameSeconds: 3.5))
    }

    func testCopyActionAndWebAppNote() {
        let model = model()
        XCTAssertEqual(model.actionTitle, "Export…")
        XCTAssertFalse(model.showsWebAppNote)
        model.options.format = .clipboard
        XCTAssertEqual(model.actionTitle, "Copy")
        XCTAssertEqual(model.showsWebAppNote, GuideClipboard.imagesMayBeDropped)
    }

    func testNothingToExportWithEmptySession() {
        manifest.steps = []
        XCTAssertFalse(model().canExport)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'ClipprTests.(SettingsStoreTests|ExportSheetModelTests)'`
Expected: build fails with `error: value of type 'SettingsStore' has no member 'exportOptions'` and `error: cannot find 'ExportSheetModel' in scope`.

- [ ] **Step 3: Add persistence to SettingsStore**

In `Sources/Clipr/Settings/SettingsStore.swift`, extend `Key`:

```swift
        static let advancedMode = "advancedMode"
        static let exportFormat = "exportFormat"
        static let exportIncludeZoom = "exportIncludeZoom"
        static let exportGIFFrameSeconds = "exportGIFFrameSeconds"
    }
```

and insert directly above `private func decoded<T: Decodable>(_ key: String) -> T? {`:

```swift
    /// The export sheet's starting options: the last format, close-up choice and GIF frame time,
    /// with `title` (per session, so never remembered). An unknown format (a newer build's) reads
    /// as PDF; a frame time outside 1–5 s is clamped.
    func exportOptions(title: String) -> ExportOptions {
        let format = defaults.string(forKey: Key.exportFormat).flatMap(GuideFormat.init(rawValue:)) ?? .pdf
        let seconds = defaults.object(forKey: Key.exportGIFFrameSeconds) as? Double ?? 2
        return ExportOptions(format: format, title: title, includeZoom: defaults.bool(forKey: Key.exportIncludeZoom),
                             gifFrameSeconds: GIFGuideExporter.clampedFrameSeconds(seconds))
    }

    func rememberExportOptions(_ options: ExportOptions) {
        defaults.set(options.format.rawValue, forKey: Key.exportFormat)
        defaults.set(options.includeZoom, forKey: Key.exportIncludeZoom)
        defaults.set(options.gifFrameSeconds, forKey: Key.exportGIFFrameSeconds)
    }
```

- [ ] **Step 4: Write the sheet model**

Create `Sources/Clipr/AdvancedMode/Export/ExportSheetModel.swift`:

```swift
// Sources/Clipr/AdvancedMode/Export/ExportSheetModel.swift
import Foundation

/// The export sheet's state, seeded from the Review session and the last export's choices.
@MainActor
final class ExportSheetModel: ObservableObject {
    @Published var options: ExportOptions
    /// Export only the selected steps. Offered (and on by default) only when Review has a selection.
    @Published var useSelection: Bool

    let selectionCount: Int
    let totalCount: Int

    private let manifest: SessionManifest
    private let folder: URL
    private let selection: Set<UUID>
    private let settings: SettingsStore

    init(manifest: SessionManifest, folder: URL, selection: Set<UUID>, settings: SettingsStore) {
        let live = selection.intersection(manifest.steps.map(\.id))
        self.manifest = manifest
        self.folder = folder
        self.selection = live
        self.settings = settings
        selectionCount = live.count
        totalCount = manifest.steps.count
        options = settings.exportOptions(title: folder.lastPathComponent)
        useSelection = !live.isEmpty
    }

    var stepCount: Int { useSelection ? selectionCount : totalCount }
    var canExport: Bool { stepCount > 0 }
    var actionTitle: String { options.format == .clipboard ? "Copy" : "Export…" }
    var showsWebAppNote: Bool { options.format == .clipboard && GuideClipboard.imagesMayBeDropped }

    func makeDocument() -> GuideDocument {
        GuideDocument.make(manifest: manifest, folder: folder, selection: useSelection ? selection : [], options: options)
    }

    func rememberOptions() {
        settings.rememberExportOptions(options)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter 'ClipprTests.(SettingsStoreTests|ExportSheetModelTests)'`
Expected: `Executed 14 tests, with 0 failures` (9 SettingsStore, 5 ExportSheetModel).

- [ ] **Step 6: Commit**

```bash
git add Sources/Clipr/Settings/SettingsStore.swift Sources/Clipr/AdvancedMode/Export/ExportSheetModel.swift Tests/ClipprTests/SettingsStoreTests.swift Tests/ClipprTests/ExportSheetModelTests.swift
git commit -m "feat: remember export choices and model the export sheet" -m "Claude-Session: https://claude.ai/code/session_01J9DeGERVvr6uhbMe87JjkA"
```

---

### Task 11: Export sheet, Review wiring (Export… and ⇧⌘E), checklist and final verification

**Files:**
- Create: `Sources/Clipr/AdvancedMode/Export/ExportSheet.swift`, `Sources/Clipr/AdvancedMode/Export/ExportFlowController.swift`
- Modify: `Sources/Clipr/AdvancedMode/ReviewView.swift` (properties, `header`, `shortcuts`), `Sources/Clipr/AdvancedMode/ReviewWindowController.swift` (properties, `init`, new `showExport()`)
- Modify: `docs/superpowers/checklists/advanced-mode-capture-manual.md`

**Interfaces:**
- Consumes: Task 10 `ExportSheetModel`; Task 9 `GuideExporter`, `GuideWarning.summary`, `GuideExportError`; Task 4 `MarkdownGuideWriter.hasExistingGuide(in:)`, `.fileName`; Task 1 `GuideFormat.suggestedFileName(for:)`, `.title`; Task 8 `GuideClipboard.webAppNote`; existing `ReviewModel.flush()`, `.manifest`, `.folder`, `.selection`.
- Produces:
  - `struct ExportSheet: View { init(model: ExportSheetModel, onCancel: () -> Void, onExport: () -> Void) }`, `@MainActor final class ExportProgress: ObservableObject { @Published var fraction: Double }`, `struct ExportProgressView: View { init(progress: ExportProgress, title: String, onCancel: () -> Void) }`
  - `@MainActor final class ExportFlowController { init(window: NSWindow, settings: SettingsStore, exporter: GuideExporter? = nil); var isActive: Bool; func begin(manifest: SessionManifest, folder: URL, selection: Set<UUID>) }`
  - `ReviewView` gains `let onExport: () -> Void` (after `onShowInFinder`); `ReviewWindowController.init(sessionFolder:storage:settings: SettingsStore = SettingsStore(), captureReplacement:)` — the existing call in `AdvancedModeCoordinator.openReview` compiles unchanged.

No unit tests here: the logic is in Tasks 9–10; this task is AppKit/SwiftUI glue, verified by build, the full suite and the manual checklist (the spec's screenshot checks).

- [ ] **Step 1: Write the sheet views**

Create `Sources/Clipr/AdvancedMode/Export/ExportSheet.swift`:

```swift
// Sources/Clipr/AdvancedMode/Export/ExportSheet.swift
import SwiftUI

/// Format, title, which steps, and the format's own options. Export hands over to the save panel;
/// Copy goes straight to the clipboard.
struct ExportSheet: View {
    @ObservedObject var model: ExportSheetModel
    let onCancel: () -> Void
    let onExport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Guide").font(.headline)
            Form {
                Picker("Format:", selection: $model.options.format) {
                    ForEach(GuideFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                TextField("Title:", text: $model.options.title)
                if model.selectionCount > 0 {
                    Picker("Steps:", selection: $model.useSelection) {
                        Text("Selected steps (\(model.selectionCount))").tag(true)
                        Text("All steps (\(model.totalCount))").tag(false)
                    }
                    .pickerStyle(.radioGroup)
                }
                if model.options.format == .gif {
                    LabeledContent("Frame time:") {
                        HStack {
                            Slider(value: $model.options.gifFrameSeconds, in: ExportOptions.gifFrameRange, step: 0.5)
                            Text(String(format: "%.1f s", model.options.gifFrameSeconds))
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                } else {
                    // GIF frames show only the step image, so close-ups don't apply there.
                    Toggle("Include close-ups", isOn: $model.options.includeZoom)
                }
            }
            if model.showsWebAppNote {
                Label(GuideClipboard.webAppNote, systemImage: "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(model.actionTitle, action: onExport)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canExport)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

@MainActor
final class ExportProgress: ObservableObject {
    @Published var fraction: Double = 0
}

struct ExportProgressView: View {
    @ObservedObject var progress: ExportProgress
    let title: String
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ProgressView(value: progress.fraction)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
```

- [ ] **Step 2: Write the flow controller**

Create `Sources/Clipr/AdvancedMode/Export/ExportFlowController.swift`:

```swift
// Sources/Clipr/AdvancedMode/Export/ExportFlowController.swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drives one export from a Review window: options sheet → save panel (or folder panel, with a
/// Replace check for Markdown) → progress sheet with Cancel → reveal in Finder, or an alert.
/// Every panel and sheet is attached to the Review window, so only one export runs per window.
@MainActor
final class ExportFlowController {
    private weak var window: NSWindow?
    private let settings: SettingsStore
    private let exporter: GuideExporter
    private var sheetWindow: NSWindow?
    private var task: Task<Void, Never>?

    /// `exporter` nil means the real one; it can't be a default argument because default
    /// arguments are evaluated outside the main actor.
    init(window: NSWindow, settings: SettingsStore, exporter: GuideExporter? = nil) {
        self.window = window
        self.settings = settings
        self.exporter = exporter ?? GuideExporter()
    }

    var isActive: Bool { sheetWindow != nil || task != nil }

    func begin(manifest: SessionManifest, folder: URL, selection: Set<UUID>) {
        guard !isActive, let window else { return }
        let model = ExportSheetModel(manifest: manifest, folder: folder, selection: selection, settings: settings)
        let sheet = ExportSheet(
            model: model,
            onCancel: { [weak self] in self?.endSheet() },
            onExport: { [weak self] in self?.confirm(model) }
        )
        present(NSHostingController(rootView: sheet), on: window)
    }

    private func present<Content: View>(_ controller: NSHostingController<Content>, on window: NSWindow) {
        let sheet = NSWindow(contentViewController: controller)
        sheetWindow = sheet
        window.beginSheet(sheet)
    }

    private func endSheet() {
        guard let sheet = sheetWindow else { return }
        window?.endSheet(sheet)
        sheetWindow = nil
    }

    private func confirm(_ model: ExportSheetModel) {
        model.rememberOptions()
        let doc = model.makeDocument()
        let options = model.options
        endSheet()
        if options.format == .clipboard { return run(doc, options: options, destination: nil) }
        // The options sheet must finish closing before the panel can attach to the same window.
        DispatchQueue.main.async { [weak self] in
            self?.chooseDestination(for: options, title: doc.title) { url in
                guard let url else { return }
                self?.run(doc, options: options, destination: url)
            }
        }
    }

    private func chooseDestination(for options: ExportOptions, title: String, completion: @escaping (URL?) -> Void) {
        guard let window else { return completion(nil) }
        if options.format == .markdown {
            let panel = NSOpenPanel()
            panel.title = "Export Markdown"
            panel.message = "Choose a folder for guide.md and its images."
            panel.prompt = "Export"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let folder = panel.url else { return completion(nil) }
                guard MarkdownGuideWriter.hasExistingGuide(in: folder) else { return completion(folder) }
                DispatchQueue.main.async { self?.confirmReplace(in: folder, completion: completion) }
            }
        } else {
            let panel = NSSavePanel()
            panel.title = "Export \(options.format.title)"
            panel.nameFieldStringValue = options.format.suggestedFileName(for: title)
            panel.allowedContentTypes = [Self.contentType(for: options.format)]
            panel.canCreateDirectories = true
            panel.beginSheetModal(for: window) { response in
                completion(response == .OK ? panel.url : nil)
            }
        }
    }

    private static func contentType(for format: GuideFormat) -> UTType {
        switch format {
        case .pdf: return .pdf
        case .html: return .html
        case .gif: return .gif
        case .markdown, .clipboard: return .folder
        }
    }

    private func confirmReplace(in folder: URL, completion: @escaping (URL?) -> Void) {
        guard let window else { return completion(nil) }
        let alert = NSAlert()
        alert.messageText = "“guide.md” already exists in “\(folder.lastPathComponent)”."
        alert.informativeText = "Replacing it overwrites guide.md and the images folder."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            completion(response == .alertFirstButtonReturn ? folder : nil)
        }
    }

    private func run(_ doc: GuideDocument, options: ExportOptions, destination: URL?) {
        guard let window else { return }
        let progress = ExportProgress()
        let title = options.format == .clipboard ? "Copying guide…" : "Exporting \(options.format.title)…"
        present(NSHostingController(rootView: ExportProgressView(
            progress: progress, title: title, onCancel: { [weak self] in self?.task?.cancel() }
        )), on: window)
        let exporter = self.exporter
        task = Task { [weak self] in
            let outcome: Result<[GuideWarning], Error>
            do {
                outcome = .success(try await exporter.export(doc, options: options, to: destination,
                                                             progress: { progress.fraction = $0 }))
            } catch {
                outcome = .failure(error)
            }
            guard let self else { return }
            self.task = nil
            self.endSheet()
            // As with the panels: let the progress sheet finish closing before an alert attaches.
            DispatchQueue.main.async { self.finish(outcome, options: options, destination: destination) }
        }
    }

    private func finish(_ outcome: Result<[GuideWarning], Error>, options: ExportOptions, destination: URL?) {
        switch outcome {
        case .success(let warnings):
            if let destination {
                let revealed = options.format == .markdown
                    ? destination.appendingPathComponent(MarkdownGuideWriter.fileName)
                    : destination
                NSWorkspace.shared.activateFileViewerSelecting([revealed])
            }
            if let summary = GuideWarning.summary(warnings) {
                showAlert("Exported with warnings", summary, style: .informational)
            }
        case .failure(let error):
            if (error as? GuideExportError) == .cancelled { return }
            showAlert(options.format == .clipboard ? "Copy Failed" : "Export Failed", error.localizedDescription, style: .warning)
        }
    }

    private func showAlert(_ message: String, _ detail: String, style: NSAlert.Style) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = style
        alert.beginSheetModal(for: window)
    }
}
```

- [ ] **Step 3: Wire Review**

Apply this diff (`git apply` from the repo root, or make the same edits by hand):

```diff
diff --git a/Sources/Clipr/AdvancedMode/ReviewView.swift b/Sources/Clipr/AdvancedMode/ReviewView.swift
index 3c13451..c133474 100644
--- a/Sources/Clipr/AdvancedMode/ReviewView.swift
+++ b/Sources/Clipr/AdvancedMode/ReviewView.swift
@@ -7,6 +7,7 @@ struct ReviewView: View {
     let onRetake: (StepRecord) -> Void
     let onReplaceWithFile: (StepRecord) -> Void
     let onShowInFinder: () -> Void
+    let onExport: () -> Void
 
     @State private var editingID: UUID?
     /// Same key as `SettingsStore.reviewLayout`, so every Review window opens in the last choice.
@@ -67,6 +68,9 @@ struct ReviewView: View {
             Button("Delete Selected", role: .destructive) { model.deleteSelection() }
                 .disabled(model.selection.isEmpty || model.isReadOnly)
             Button("Show in Finder", action: onShowInFinder)
+            Button("Export…", action: onExport)
+                .disabled(model.manifest.steps.isEmpty)
+                .help("Export the guide (⇧⌘E)")
         }
         .padding(.horizontal, 16)
         .padding(.vertical, 10)
@@ -118,6 +122,9 @@ struct ReviewView: View {
             Button("") { model.stepImageSize(by: -1) }
                 .keyboardShortcut("-", modifiers: .command)
                 .disabled(editingID != nil || model.isReadOnly || model.selection.isEmpty)
+            Button("") { onExport() }
+                .keyboardShortcut("e", modifiers: [.command, .shift])
+                .disabled(editingID != nil || model.manifest.steps.isEmpty)
             // ⌘1 / ⌘2 / ⌘3, as Finder does for its views.
             ForEach(Array(ReviewLayout.allCases.enumerated()), id: \.element) { index, option in
                 Button("") { layout = option }
diff --git a/Sources/Clipr/AdvancedMode/ReviewWindowController.swift b/Sources/Clipr/AdvancedMode/ReviewWindowController.swift
index b3c799e..d3f555c 100644
--- a/Sources/Clipr/AdvancedMode/ReviewWindowController.swift
+++ b/Sources/Clipr/AdvancedMode/ReviewWindowController.swift
@@ -4,6 +4,9 @@ import UniformTypeIdentifiers
 
 final class ReviewWindowController: NSWindowController, NSWindowDelegate {
     private let storage: StorageManager
+    private let settings: SettingsStore
+    /// Set once the window exists; owns the export sheets and the running export.
+    private var exportFlow: ExportFlowController?
     private let model: ReviewModel
     private let captureReplacement: (@escaping (NSImage?) -> Void) -> Void
     let sessionFolder: URL
@@ -16,8 +19,10 @@ final class ReviewWindowController: NSWindowController, NSWindowDelegate {
     var windowID: CGWindowID? { window.map { CGWindowID($0.windowNumber) } }
 
     @MainActor
-    init(sessionFolder: URL, storage: StorageManager, captureReplacement: @escaping (@escaping (NSImage?) -> Void) -> Void) {
+    init(sessionFolder: URL, storage: StorageManager, settings: SettingsStore = SettingsStore(),
+         captureReplacement: @escaping (@escaping (NSImage?) -> Void) -> Void) {
         self.storage = storage
+        self.settings = settings
         self.captureReplacement = captureReplacement
         self.sessionFolder = sessionFolder
         model = ReviewModel(folder: sessionFolder)
@@ -36,8 +41,10 @@ final class ReviewWindowController: NSWindowController, NSWindowDelegate {
             onOpenEditor: { [weak self] step in self?.openEditor(for: step) },
             onRetake: { [weak self] step in self?.retake(step) },
             onReplaceWithFile: { [weak self] step in self?.replaceWithFile(step) },
-            onShowInFinder: { NSWorkspace.shared.activateFileViewerSelecting([sessionFolder]) }
+            onShowInFinder: { NSWorkspace.shared.activateFileViewerSelecting([sessionFolder]) },
+            onExport: { [weak self] in self?.showExport() }
         ))
+        exportFlow = ExportFlowController(window: window, settings: settings)
         window.center()
     }
 
@@ -77,6 +84,15 @@ final class ReviewWindowController: NSWindowController, NSWindowDelegate {
         MainActor.assumeIsolated { model.flush() }
     }
 
+    /// Exports what Review shows now: a caption typed in the last half-second is saved first, so
+    /// the guide has it. Read-only sessions export too — exporting never writes to the session.
+    private func showExport() {
+        MainActor.assumeIsolated {
+            model.flush()
+            exportFlow?.begin(manifest: model.manifest, folder: model.folder, selection: model.selection)
+        }
+    }
+
     /// The capture overlay hides Clipr's windows (this one included) while it's up and restores
     /// them afterwards, so the user can capture whatever was behind Review.
     private func retake(_ step: StepRecord) {
```

- [ ] **Step 4: Build and run the full suite**

Run: `swift build && swift test`
Expected: clean build with no errors and no new warnings in `AdvancedMode/Export/`, `ReviewView.swift` or `ReviewWindowController.swift`; full suite `with 0 failures`, 71 tests more than before Task 1 (430 when run on top of commit `5e9a58f`).

- [ ] **Step 5: Append the Export checklist**

Append to `docs/superpowers/checklists/advanced-mode-capture-manual.md`:

```markdown
## Export
- [ ] Review's header shows **Export…**; ⇧⌘E opens the same sheet. Both are disabled when the session has no steps; ⇧⌘E does nothing while a caption is being edited.
- [ ] The sheet lists PDF, HTML, Markdown, GIF, Copy as Rich Text; Title defaults to the session folder name.
- [ ] With two steps selected the sheet offers "Selected steps (2)" (chosen) and "All steps (N)"; exporting gives just those two, numbered 1 and 2, in Review order.
- [ ] PDF: the save panel suggests "<title>.pdf"; after export Finder reveals the file. In Preview: title, grey "date · N steps" line, numbered steps with bold kept, app name in small grey text, images with their annotations (markers, trail, editor drawings), sized steps narrower, no step split across pages. Paper is A4 (Letter when the Mac's region is US).
- [ ] HTML: opens in Safari looking like the PDF; move the file to another folder and reopen → images still show (embedded).
- [ ] Markdown: choose a folder → it contains `guide.md` and `images/step-01.png`…; the guide renders on GitHub with images, Small/Medium/Large steps narrower than Full ones.
- [ ] Markdown again into the same folder → "“guide.md” already exists…" → Cancel leaves the folder untouched; Replace overwrites guide.md and images/.
- [ ] GIF: one frame per step, same size throughout, caption band underneath ("Step N" when no caption), loops forever; the Frame time slider (1–5 s) changes the pace; posted in Slack it animates.
- [ ] Include close-ups on (session recorded with Zoom on click): the close-up sits beside the image in HTML/PDF and follows the image line in Markdown; off → no close-ups. The toggle is hidden for GIF.
- [ ] Copy as Rich Text: the action button reads "Copy"; the web-app note shows if the clipboard spike recorded dropped images. Paste into TextEdit, Google Docs, Notion and Confluence and compare with the spike table above.
- [ ] Reopen the sheet → last format, close-ups choice and frame time are remembered; Title is the folder name again.
- [ ] With Review open, move one step's PNG out of the session folder in Finder, then export HTML → that step shows "Image unavailable" and an alert lists the step.
- [ ] Replace a step's `_annotations.json` contents with `x`, export → the step's image appears without annotations and an alert says its annotations couldn't be read.
- [ ] Start a PDF export of a long session and press Cancel in the progress sheet → no file at the chosen location.
- [ ] Export into a folder you can't write to (e.g. `chmod 555` a test folder) → "Export Failed" alert explaining the location couldn't be written; nothing appears there.
- [ ] Hand-edit `session.json` "version" to 2 (read-only session) → Export still works.
```

- [ ] **Step 6: Build the app and run the checklist and screenshot checks**

Run: `./Scripts/build-app.sh`
Expected: ends with `Built …/Clipr.app`. Do not stage `Clipr.app`.

Open the app, record a short session (or open an existing one with Review), and work through the new "Export" checklist section, ticking each item. Take two screenshots for the PR description: the export sheet (`screencapture -w "$TMPDIR/export-sheet.png"`, click the Review window with the sheet open) and an exported HTML guide open in Safari (`screencapture -w "$TMPDIR/export-html.png"`). Any item that fails is fixed before committing, with a test where the logic lives in Tasks 1–10.

- [ ] **Step 7: Commit**

```bash
git add Sources/Clipr/AdvancedMode/Export/ExportSheet.swift Sources/Clipr/AdvancedMode/Export/ExportFlowController.swift Sources/Clipr/AdvancedMode/ReviewView.swift Sources/Clipr/AdvancedMode/ReviewWindowController.swift docs/superpowers/checklists/advanced-mode-capture-manual.md
git commit -m "feat: export sheet in Review with Export… and ⇧⌘E" -m "Claude-Session: https://claude.ai/code/session_01J9DeGERVvr6uhbMe87JjkA"
```
