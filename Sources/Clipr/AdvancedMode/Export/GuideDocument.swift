import Foundation
import CoreGraphics

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
                zoom: options.includeZoom ? closeUpRef(record, folder: folder) : nil
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
        DateFormats.string(date, pattern: "d MMM yyyy", timeZone: timeZone)
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func ref(_ url: URL) -> GuideImageRef {
        FileManager.default.fileExists(atPath: url.path) ? .file(url) : .missing
    }

    /// A close-up whose capture-time file is gone is simply left out: it's an extra, not the step
    /// itself. The file name is derived from the step's, never taken from `zoomFile`, so a crafted
    /// session.json can't point the export at a file outside the session.
    private static func closeUpRef(_ record: StepRecord, folder: URL) -> GuideImageRef? {
        guard record.zoomFile != nil, let clickPoint = record.clickPoint else { return nil }
        let zoom = folder.appendingPathComponent(FilenameGenerator.zoomName(fromStep: record.file))
        guard FileManager.default.fileExists(atPath: zoom.path) else { return nil }
        return .closeUp(CloseUpSource(step: folder.appendingPathComponent(record.file), capturedZoom: zoom, clickPoint: clickPoint))
    }
}
