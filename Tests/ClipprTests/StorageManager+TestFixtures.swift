import Cocoa
import XCTest
@testable import Clipr

/// Test-only conveniences for laying out captures and sessions on disk. The app itself writes
/// session steps through `ClickCaptureManager`/`SessionFolder` and reads sidecars with
/// `readAnnotations`; these keep fixtures short.
extension StorageManager {
    func createSessionFolder(date: Date) throws -> URL {
        try SessionFolder.create(in: baseFolder, date: date)
    }

    /// Writes `image` as `Step_NN.png`, owner-only like a captured step.
    func saveStep(_ image: NSImage, index: Int, in sessionFolder: URL) throws -> URL {
        let url = sessionFolder.appendingPathComponent(FilenameGenerator.stepName(index: index))
        try XCTUnwrap(ImageEncoding.png(image)).write(to: url, options: .atomic)
        Self.restrictToOwner(url)
        return url
    }

    /// Writes `image` as the step's `_zoom.png`, replacing any already there.
    func saveStepZoom(_ image: NSImage, stepURL: URL) throws -> URL {
        let url = stepURL.deletingLastPathComponent()
            .appendingPathComponent(FilenameGenerator.zoomName(fromStep: stepURL.lastPathComponent))
        try XCTUnwrap(ImageEncoding.png(image)).write(to: url, options: .atomic)
        Self.restrictToOwner(url)
        return url
    }

    /// The sidecar's annotations, treating a missing and an unreadable sidecar alike.
    func loadAnnotations(rawURL: URL) -> [AnnotationObject] {
        if case .loaded(let annotations) = readAnnotations(rawURL: rawURL) { return annotations }
        return []
    }

    func deleteAnnotations(rawURL: URL) {
        let sidecar = rawURL.deletingLastPathComponent()
            .appendingPathComponent(FilenameGenerator.annotationsName(fromRaw: rawURL.lastPathComponent))
        try? FileManager.default.removeItem(at: sidecar)
    }
}
