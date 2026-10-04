import Foundation
import CoreGraphics

/// Loads and saves a session's `session.json`.
enum SessionManifestStore {
    static let fileName = "session.json"
    static let currentVersion = 1

    enum StoreError: Error, Equatable { case folderUnreadable }

    static func save(_ manifest: SessionManifest, in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = folder.appendingPathComponent(fileName)
        try encoder.encode(manifest).write(to: url, options: .atomic)
        // Captions can hold what the user typed: owner-only, like every other session file. An
        // atomic write replaces the file, so this is needed on every save, Review's included.
        SessionFolder.restrict(url)
    }

    /// Review saves after every edit. If the folder can't be listed (permissions changed, an
    /// external drive went away) the in-memory manifest may have been built from an empty listing,
    /// so writing it could erase every caption — refuse instead and let the caller retry.
    static func saveSafely(_ manifest: SessionManifest, in folder: URL) throws {
        guard (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) != nil else {
            throw StoreError.folderUnreadable
        }
        try save(manifest, in: folder)
    }

    /// A manifest written by a newer Clipr may carry meaning this build doesn't understand, so
    /// Review shows it but never writes it back.
    static func isReadOnly(_ manifest: SessionManifest) -> Bool {
        manifest.version > currentVersion
    }

    /// Why Review must not write a session's `session.json`.
    enum ReadOnlyReason: Equatable {
        /// Written by a newer Clipr: it may carry meaning this build doesn't understand.
        case newerVersion
        /// Present but not decodable as a manifest this build understands. Rewriting it from the
        /// PNGs (what `load` falls back to) would erase every caption in it.
        case unreadable
    }

    /// `load(from:)` plus whether Review may write the result back. A missing `session.json` is
    /// writable (sessions from before the manifest existed); one that exists but doesn't fully
    /// decode never is — even when its version is ours, since the rebuilt manifest would drop
    /// whatever the file held.
    static func loadForReview(from folder: URL) -> (manifest: SessionManifest, readOnly: ReadOnlyReason?) {
        let manifest = load(from: folder)
        let url = folder.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return (manifest, nil) }
        guard let data = try? Data(contentsOf: url) else { return (manifest, .unreadable) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Checked first so a newer manifest gets the newer-version notice whether or not this
        // build happens to decode the rest of it.
        if let header = try? decoder.decode(VersionHeader.self, from: data), header.version > currentVersion {
            return (manifest, .newerVersion)
        }
        guard (try? decoder.decode(SessionManifest.self, from: data)) != nil else { return (manifest, .unreadable) }
        return (manifest, nil)
    }

    /// Just enough of `session.json` to read its version when the rest won't decode.
    private struct VersionHeader: Decodable { let version: Int }

    /// Always returns a manifest that matches the folder's contents: entries whose PNG is gone are
    /// dropped and raw step PNGs with no entry are appended as `.manual` steps without captions.
    /// A missing or unreadable `session.json` (sessions recorded before the manifest existed, or a
    /// failed write) therefore still yields every step instead of an empty session.
    static func load(from folder: URL) -> SessionManifest {
        let onDisk = rawStepFiles(in: folder)
        var manifest = decoded(from: folder) ?? SessionManifest(createdAt: creationDate(of: folder))
        // A duplicate entry would show one file twice and make reorder/delete ambiguous.
        var seen = Set<String>()
        manifest.steps = manifest.steps.filter { seen.insert($0.file).inserted }
        // Ids must be unique too: Review keys steps by id. A repeat (a hand-edited or sync-merged
        // session.json) keeps its file and caption under a fresh id.
        var seenIDs = Set<UUID>()
        for index in manifest.steps.indices where !seenIDs.insert(manifest.steps[index].id).inserted {
            manifest.steps[index] = manifest.steps[index].withNewID()
        }
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
            .filter(FilenameGenerator.isRawStepName)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func decoded(from folder: URL) -> SessionManifest? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var manifest = try? decoder.decode(SessionManifest.self, from: data) else { return nil }
        // Full is always nil (an unknown size from a newer build decodes as .full), so there is one
        // way to say Full and setting Full on such a step is a no-op rather than a phantom edit.
        for index in manifest.steps.indices where manifest.steps[index].imageSize == .full {
            manifest.steps[index].imageSize = nil
        }
        return manifest
    }

    private static func creationDate(of folder: URL) -> Date {
        (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
    }
}
