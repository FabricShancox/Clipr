import Foundation

/// Each capture's annotations sidecar: save, read, and set aside when unreadable.
extension StorageManager {
    /// Persists the live, editable annotation objects for a capture as a JSON sidecar, so
    /// reopening it from Recents (or relaunching Clipr entirely) restores actual editable
    /// annotations rather than only a flattened preview image. Called alongside
    /// `saveEditedCapture` on every auto-save.
    ///
    /// No annotations means no sidecar. Writing `[]` put an `X_annotations.json` beside every
    /// capture merely viewed in the editor — and beside images opened from elsewhere — and failed
    /// (logged only) on read-only folders. An empty save instead removes any sidecar left over,
    /// including stale `[]` files from earlier builds; a missing sidecar already loads as "none".
    func saveAnnotations(_ annotations: [AnnotationObject], rawURL: URL) throws {
        let url = annotationsURL(forRaw: rawURL)
        guard !annotations.isEmpty else {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        let data = try JSONEncoder().encode(annotations)
        try Self.createPrivateFolder(url.deletingLastPathComponent())
        try data.write(to: url, options: .atomic)
        Self.restrictToOwner(url)
    }

    /// Outcome of reading a capture's annotation sidecar. `missing` and `corrupt` are deliberately
    /// distinct: collapsing both to "no annotations" meant an unreadable sidecar looked like a
    /// never-edited capture, and the next auto-save then overwrote it — destroying the user's
    /// annotations permanently, with nothing shown to them.
    enum AnnotationsLoad {
        /// No sidecar yet — a fresh, never-edited capture.
        case missing
        case loaded([AnnotationObject])
        /// The sidecar exists but could not be decoded. The caller must not let it be overwritten.
        case corrupt(Error)
    }

    func readAnnotations(rawURL: URL) -> AnnotationsLoad {
        let url = annotationsURL(forRaw: rawURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            // Size-checked before reading and range-checked after decoding — see `DecodeLimits`.
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard bytes <= DecodeLimits.maxSidecarBytes else { throw SidecarLimitError.tooLarge(bytes: bytes) }
            let annotations = try JSONDecoder().decode([AnnotationObject].self, from: Data(contentsOf: url))
            guard DecodeLimits.areAcceptable(annotations) else { throw SidecarLimitError.outOfRange }
            return .loaded(annotations)
        } catch {
            return .corrupt(error)
        }
    }

    /// Moves an unreadable sidecar aside, returning where it went.
    ///
    /// Called before the editor opens a capture whose sidecar won't decode, so the next auto-save
    /// writes a fresh file instead of overwriting one whose contents might still be recoverable by
    /// hand. Never deletes anything.
    @discardableResult
    func quarantineAnnotations(rawURL: URL) -> URL? {
        let url = annotationsURL(forRaw: rawURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let backup = uniqueURL(for: url.appendingPathExtension("bak"))
        do {
            try FileManager.default.moveItem(at: url, to: backup)
            return backup
        } catch {
            NSLog("Clipr: could not set aside unreadable annotations for \(rawURL.lastPathComponent): \(error)")
            return nil
        }
    }

    func annotationsURL(forRaw rawURL: URL) -> URL {
        rawURL.deletingLastPathComponent().appendingPathComponent(FilenameGenerator.annotationsName(fromRaw: rawURL.lastPathComponent))
    }
}
