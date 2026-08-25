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
                        canvasScale: canvasScale,
                        onAnnotationCommitted: handleAnnotationCommitted,
                        onCropRequested: { rect in onCropApplied(rect, annotations) }
                    )
                    canvasResizeHandles
                }
                .scaleEffect(canvasScale, anchor: .topLeading)
                .frame(width: image.size.width * canvasScale, height: image.size.height * canvasScale)
                .padding(24)
            }
            .background(EditorColors.s0)
            .onAppear {
                viewportSize = geo.size
                if !userSetZoom { zoomToFit() }
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
        .onChange(of: annotations) { _, _ in
            scheduleAutoSave()
        }
    }

    /// Scales so the full image fits the visible scroll viewport, never upscaling past 100% —
    /// this is the fix for "the capture is too zoomed in to see all of it": rather than always
    /// opening at a fixed 1:1 size, a capture larger than the window now starts scaled down to
    /// fit, and the user can zoom back in or drag-scroll as needed.
    func zoomToFit() {
        guard viewportSize.width > 0, viewportSize.height > 0, image.size.width > 0, image.size.height > 0 else { return }
        let scaleX = (viewportSize.width - 48) / image.size.width
        let scaleY = (viewportSize.height - 48) / image.size.height
        let fitScale = max(min(scaleX, scaleY), 0.05)
        zoomPercent = (min(fitScale, 1.0) * 100).rounded()
    }
}
