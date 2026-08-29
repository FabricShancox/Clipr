import SwiftUI

/// The zoomable/scrollable canvas area. See `EditorView.swift`'s header for how this file
/// relates to the rest of the type.
extension EditorView {
    var canvasScale: CGFloat { zoomPercent / 100 }

    var zoomControl: some View {
        HStack(spacing: 2) {
            Button {
                userSetZoom = true
                zoomPercent = max(10, zoomPercent - 10)
            } label: { Image(systemName: "minus").frame(width: 22, height: 22).contentShape(Rectangle()) }
                .help("Zoom out")
            Text("\(Int(zoomPercent))%")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 40)
                .foregroundColor(EditorColors.t1)
            Button {
                userSetZoom = true
                zoomPercent = min(400, zoomPercent + 10)
            } label: { Image(systemName: "plus").frame(width: 22, height: 22).contentShape(Rectangle()) }
                .help("Zoom in")
            Button {
                // Re-requesting Fit explicitly hands auto-fit-on-resize control back, so a
                // later window resize keeps tracking it rather than staying locked at whatever
                // zoom the user had set manually before.
                userSetZoom = false
                zoomToFit()
            } label: {
                Text("Fit").frame(height: 22).padding(.horizontal, 4).contentShape(Rectangle())
            }
            .foregroundColor(EditorColors.accent)
            .help("Fit the whole capture in the window")
        }
        .buttonStyle(.plain)
        .foregroundColor(EditorColors.t1)
        .padding(6)
        .background(EditorColors.s1)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(EditorColors.line, lineWidth: 1))
    }

    var canvasArea: some View {
        GeometryReader { geo in
            // The scale actually used to size the scrollable content this render. While
            // auto-fitting it's derived straight from `geo.size` rather than read back from
            // `zoomPercent`, so the first frame already lays out at the fitted size instead of
            // rendering full-size and being shrunk by a follow-up state update. `zoomPercent`
            // still drives the zoom once the user takes manual control.
            let renderScale = userSetZoom ? canvasScale : fitScale(for: geo.size)
            let scaledSize = CGSize(width: image.size.width * renderScale, height: image.size.height * renderScale)
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    AnnotationCanvasView(
                        image: image,
                        annotations: annotationsBinding,
                        selectedTool: $selectedTool,
                        currentColor: $currentColor,
                        currentStrokeWidth: $currentStrokeWidth,
                        currentTextStyle: $currentTextStyle,
                        selectedID: $selectedAnnotationID,
                        editingTextID: $editingTextID,
                        canvasScale: renderScale,
                        redactionStyle: redactionStyle,
                        onAnnotationCommitted: handleAnnotationCommitted,
                        onCropRequested: { rect in onCropApplied(rect, annotations) }
                    )
                    canvasResizeHandles
                }
                // `canvasResizeHandles` positions its corners with `.position()`, which makes it
                // a flexible view that expands to fill whatever space is offered. Without pinning
                // the stack to the image's natural size here, the scaled frame below offers it
                // the (larger) scaled size, the stack grows to that, and the fixed-size canvas
                // gets centred inside the grown stack — which the `.scaleEffect` then multiplies
                // into a large offset, pushing the image off-screen when zoomed past 100%.
                .frame(width: image.size.width, height: image.size.height)
                .scaleEffect(renderScale, anchor: .topLeading)
                // `scaleEffect` scales rendering only — the canvas still reports its full,
                // unscaled `image.size` for layout. So this frame must pin that (larger) child
                // to its top-leading corner, matching the scale anchor, for the scaled render to
                // land exactly inside it. Leaving the default centre alignment offsets the child
                // by half the difference between the two sizes and the image drifts off-canvas.
                .frame(width: scaledSize.width, height: scaledSize.height, alignment: .topLeading)
                .padding(24)
                // Centres the canvas in the viewport. `max` keeps this at least the true content
                // size when zoomed in past what fits, so `ScrollView` still has scroll range —
                // a fixed `frame` smaller than the content would just clip it.
                .frame(
                    width: max(geo.size.width, scaledSize.width + 48),
                    height: max(geo.size.height, scaledSize.height + 48),
                    alignment: .center
                )
            }
            .background(EditorColors.s0)
            .onAppear {
                viewportSize = geo.size
                if !userSetZoom { zoomPercent = (renderScale * 100).rounded() }
            }
            .onChange(of: geo.size) { _, newSize in
                viewportSize = newSize
                // Keeps re-fitting on every layout pass until the user manually takes zoom
                // control — a `GeometryReader` can report several different transient sizes
                // while the window's initial layout settles (e.g. right after opening
                // maximized), so treating any single non-zero read as "done" risked locking in
                // on a still-wrong intermediate size. Cheap to just keep converging instead.
                if !userSetZoom { zoomToFit() }
            }
        }
        .onChange(of: annotations) { _, newValue in
            // Report the new state immediately, then debounce the actual write. The controller
            // needs the current annotations the moment they change so it can still save them if
            // the window closes before the debounce elapses.
            onAnnotationsChanged(newValue)
            scheduleAutoSave()
        }
    }

    /// Scale at which the full image fits the given viewport, never upscaling past 100% —
    /// this is the fix for "the capture is too zoomed in to see all of it": rather than always
    /// opening at a fixed 1:1 size, a capture larger than the window now starts scaled down to
    /// fit, and the user can zoom back in or drag-scroll as needed.
    func fitScale(for viewport: CGSize) -> CGFloat {
        guard viewport.width > 0, viewport.height > 0, image.size.width > 0, image.size.height > 0 else { return 1 }
        let scaleX = (viewport.width - 48) / image.size.width
        let scaleY = (viewport.height - 48) / image.size.height
        return max(min(min(scaleX, scaleY), 1.0), 0.05)
    }

    /// Syncs `zoomPercent` (the displayed/persisted zoom) to match the current auto-fit scale —
    /// purely cosmetic for the zoom-control label; the actual rendered size comes from
    /// `fitScale(for:)` directly, see `canvasArea`.
    func zoomToFit() {
        zoomPercent = (fitScale(for: viewportSize) * 100).rounded()
    }
}
