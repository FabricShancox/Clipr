# Advanced Mode Export — Design

Date: 2026-10-04
Status: Approved (design), pending spec review
Sub-project 3 of 3 (1: Capture — shipped; 2: Review — shipped).

## Context and intent

Advanced Mode sessions become **how-to guides**. Review (sub-project 2) lets the user order,
caption, size and prune steps. Export turns the reviewed session into something shareable.
Guides go to a mix of destinations, so each format is shaped for its natural one:

| Format | Shape | Destination |
|---|---|---|
| PDF | One paginated file | Email, Slack, tickets |
| HTML | One self-contained `.html` (images embedded as data URIs) | Sharing a file, opening in a browser |
| Markdown | Folder: `guide.md` + `images/`, relative links | GitHub, MkDocs, wikis, Notion import |
| GIF | Animated slideshow, caption band per frame | Chat, READMEs |
| Copy as Rich Text | Guide on the clipboard (HTML + RTF) | Pasting into Confluence, Notion, Google Docs |

## Decisions

- **One HTML template drives HTML, PDF and the clipboard (approach A).** The PDF is that HTML
  printed through WebKit with page-break rules; the clipboard carries the same HTML (plus RTF).
  Markdown and GIF have their own writers.
- Export lives in Review: an **Export…** toolbar button (⇧⌘E) opens an export sheet.
- Steps exported: the **selection** if any, otherwise **all**, in Review order, renumbered 1…N.
- Images are the step's raw PNG with its annotation sidecar **flattened on** (markers, trail and
  editor drawings), so exports match Review/the editor.
- Each step's `imageSize` (S/M/L/Full, nil = Full) sets its width: 40% / 60% / 80% / 100% of the
  content width.
- Light theme only, system font stack — predictable in print and when pasted.

## Architecture

| Unit | Kind | Responsibility |
|---|---|---|
| `GuideDocument` | Pure value | `title`, `date`, `steps: [GuideStep]` where `GuideStep { number: Int; caption: String? (Markdown); appName: String?; imageSize: ImageSize; image: GuideImageRef; zoom: GuideImageRef? }`. Built by `GuideDocument.make(manifest:folder:selection:options:)` from the session manifest, the Review selection and `ExportOptions`. |
| `GuideImageRef` | Pure value | `.file(URL)` (raw step PNG + sidecar URL) or `.missing`. Rendering is deferred to `GuideImages`. |
| `GuideImages` | Image IO | `render(_ ref:, maxPixelWidth:) -> GuideImage?` — loads the raw PNG, loads annotations via `StorageManager.loadAnnotations`, flattens with `AnnotationRenderer.flatten`, downsamples to `maxPixelWidth` (Full 1600px, others proportional), encodes PNG (JPEG q0.85 when the PNG would exceed 1.5 MB). Returns data + pixel size. Damaged sidecar → raw image + a warning. |
| `CaptionMarkup` | Pure | `html(_ markdown: String?, fallbackNumber:) -> String` — inline Markdown → HTML keeping bold/italic/code only; links, images, autolinks and raw HTML stripped to text; everything HTML-escaped. `markdown(_:fallbackNumber:) -> String` — re-emits safe Markdown: links/images/HTML reduced to text, backslash, backtick, `[`, `]`, `<`, `>`, `_` escaped where not part of kept emphasis. Empty/nil → "Step N". |
| `HTMLGuideWriter` | Pure | `write(_ doc:, images: [Int: GuideImage], mode: .embedded | .linked(prefix:)) -> String` — full document with inline CSS; step blocks use `break-inside: avoid`; zoom inset floats beside the image, wrapping under it on narrow widths. |
| `PDFGuideExporter` | WebKit | Loads the embedded HTML in an offscreen `WKWebView`, prints via `printOperation(with:)` to a PDF file (`NSPrintInfo` job disposition save; paper A4 or US Letter by locale). 30 s timeout. |
| `MarkdownGuideWriter` | Pure + IO | `write(_ doc:) -> String` and `export(_ doc:, images:, to folder:)` writing `guide.md` and `images/step-NN.png` (positional names). Sizes as `<img src="images/step-01.png" alt="Step 1" width="60%">` for non-Full; plain `![Step N](images/step-NN.png)` for Full. |
| `GIFGuideExporter` | ImageIO | `CGImageDestination` GIF; fixed canvas (≤ 1000px wide, height from the tallest step at that width + caption band); each step image centred; caption (plain text) in a band underneath; per-frame delay 1–5 s (default 2); loop forever. |
| `GuideClipboard` | AppKit | Writes `public.html` (embedded HTML) and RTF (`NSAttributedString(html:)`) to the general pasteboard. |
| `ExportOptions` | Value + persistence | `format`, `title`, `includeZoom` (default off), `gifFrameSeconds` (default 2). Last format / includeZoom / gifFrameSeconds remembered via `SettingsStore`. |
| `GuideExporter` | Coordinator | Runs an export off the main thread with progress (per step) and cancellation; writes to a temp location and moves into place only on success; reports warnings (missing images, damaged sidecars). |
| `ExportSheet` | SwiftUI | Format picker, title field (default: session folder name), "Selected steps (N) / All steps (M)" choice when there is a selection, include close-ups toggle, GIF frame-time slider (GIF only). Export → save panel (file for PDF/HTML/GIF; folder for Markdown) or, for Copy, directly to the clipboard. Progress sheet with Cancel; on success, reveal in Finder. |

## Output layout (HTML / PDF / clipboard)

- Header: title (h1); below it in secondary grey "4 Oct 2026 · 7 steps".
- Per step: a numbered circle + caption (bold kept) as the step heading; app name in small grey
  text; then the image at its width fraction, left-aligned, 1px light border, 6px radius; zoom
  inset (if included and present) beside it at ~30% width.
- No caption → heading "Step N".
- Missing image → a light grey box with "Image unavailable".
- PDF: A4 or US Letter by locale, 18mm margins, a step never splits across pages (oversized
  images scale to fit the page).

## Markdown layout

```
# Title
_4 Oct 2026 · 7 steps_

## 1. Click **Save** in Safari
![Step 1](images/step-01.png)

## 2. Click in **Warp**
<img src="images/step-02.png" alt="Step 2" width="60%">
```

Zoom insets (if included) follow as `![Step 1 close-up](images/step-01-zoom.png)`.

## GIF layout

Fixed canvas; each frame is the step image centred, with a caption band (plain text, bold
dropped, "Step N" fallback) underneath. Loops. Frame time 1–5 s.

## Error handling

| Case | Behaviour |
|---|---|
| Step image missing/unreadable | Caption exported with an "Image unavailable" placeholder; export completes; warning lists the steps |
| Damaged annotation sidecar | Raw image without annotations; warning lists the steps |
| Destination not writable / disk full | Export stops; temp output removed; alert with the reason; nothing half-written at the destination |
| Markdown folder already has `guide.md` | Ask: Replace (overwrites `guide.md` and `images/`) or Cancel |
| PDF render fails or exceeds 30 s | Alert suggesting HTML export |
| Cancel during export | Stops before the next step; temp output removed |
| Read-only session | Export allowed (read-only) |
| Clipboard images dropped by a target app | Text still pastes; behaviour per target documented after the early spike (see Risks) |

## Risks

- **Clipboard images in web docs tools.** Google Docs, Notion and Confluence treat data-URI
  images in pasted HTML differently. The first implementation task includes a manual spike:
  paste the clipboard output into each and record what survives. If images are dropped, the
  export sheet shows a note for Copy ("Images may not paste into some web apps — use PDF or
  Markdown") and the behaviour is recorded in the checklist. No other fallback is built.
- **WebKit print pagination.** `printOperation(with:)` must paginate with `break-inside: avoid`;
  verified by the PDF integration test (page count > 1 for a long guide, every step heading
  present).

## Testing

Unit tests (XCTest):
- `GuideDocumentTests` — all vs selection, order and renumbering, sizes (nil → full), zoom on/off,
  missing image → `.missing`.
- `CaptionMarkupTests` — bold/italic/code kept; links, autolinks, images, raw HTML stripped;
  HTML escaping; Markdown escaping incl. backslash and brackets; nil/empty → "Step N".
- `HTMLGuideWriterTests` — header, step order, width per size, embedded vs linked image src,
  no `<script>`/`javascript:`/`on*=` in output for hostile captions.
- `MarkdownGuideWriterTests` — file layout, relative links, width attribute only for non-Full,
  zoom lines.
- `GIFGuideExporterTests` — decode the written GIF: frame count, per-frame delay, loop count 0,
  constant canvas size.
- `GuideImagesTests` — annotations flattened (pixel check), downsampling cap, JPEG fallback size
  rule, damaged sidecar → raw image + warning.
- `PDFGuideExporterTests` — 3-step and 30-step documents produce a PDF with pages ≥ 1 / > 1 and
  contain each step heading text (PDFKit).
- `GuideExporterTests` — cancel removes temp output; unwritable destination leaves nothing.

Screenshot checks: exported HTML (rendered) and the export sheet. Manual checklist: paste into
Google Docs, Notion, Confluence; Markdown on GitHub; GIF in Slack; PDF in Preview.

## Out of scope

- Themes, custom CSS, logos/branding.
- Editing the guide after export; re-import.
- Video export (MP4).
- Per-format image quality settings beyond the defaults above.
- Uploading/publishing to any service.
