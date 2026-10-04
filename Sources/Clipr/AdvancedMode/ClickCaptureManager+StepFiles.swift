import Cocoa

/// Turning a captured frame into a step's encoded files, and writing those files. Static and free
/// of session state, so it runs off the main thread inside the write chain.
extension ClickCaptureManager {
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
    static func captureAndPrepare(
        target: CaptureTarget, resolveTarget: (() async -> CaptureTarget)?, imageSource: StepImageSource,
        showsCursor: Bool, skipIf: () async -> Bool,
        kind: StepRecord.Kind, click: CGPoint?, appName: String?, trail: [CGPoint], settings: AdvancedModeSettings,
        caption: (_ appName: String?) async -> String?
    ) async -> PreparedStep? {
        guard await !skipIf() else { return nil }
        let target = await resolveTarget?() ?? target
        let frame: CapturedFrame?
        do {
            frame = try await imageSource.capture(target, showsCursor: showsCursor)
        } catch {
            NSLog("Clipr: advanced mode step capture failed: \(error)")
            return nil
        }
        guard var frame else { return nil }
        if let appName { frame.appName = appName }
        let text = await caption(frame.appName)
        return autoreleasepool {
            prepare(frame, kind: kind, click: click, trail: trail, caption: text, settings: settings)
        }
    }

    /// Pure: the encoded step image, its marker/trail annotations and zoom crop. Nil only if the
    /// image won't encode.
    static func prepare(_ frame: CapturedFrame, kind: StepRecord.Kind, click: CGPoint?, trail: [CGPoint],
                        caption: String?, settings: AdvancedModeSettings, capturedAt: Date = Date()) -> PreparedStep? {
        guard let png = ImageEncoding.png(frame.image) else {
            NSLog("Clipr: advanced mode step encode failed")
            return nil
        }
        // A capture that had to fall back to another window doesn't show the click: no marker,
        // trail or close-up pointing at the wrong thing.
        let click = frame.marksClick ? click : nil
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
            zoomPNG = ImageEncoding.png(zoom)
        }
        return PreparedStep(png: png, annotations: annotations, zoomPNG: zoomPNG, kind: kind, caption: caption,
                            clickPoint: imagePoint, appName: frame.appName, capturedAt: capturedAt)
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

    static func annotationsURL(for stepURL: URL) -> URL {
        stepURL.deletingLastPathComponent().appendingPathComponent(FilenameGenerator.annotationsName(fromRaw: stepURL.lastPathComponent))
    }
}
