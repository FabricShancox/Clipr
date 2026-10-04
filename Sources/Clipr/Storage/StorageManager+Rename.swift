import Foundation

/// Renaming a capture together with its `_edited` preview and annotations sidecar.
extension StorageManager {
    /// Renames a capture and the two files keyed off its name — the flattened `_edited.png` and
    /// the annotations sidecar — returning the raw file's new URL.
    ///
    /// A rename must never destroy someone else's capture, so rather than moving each file and
    /// hoping, this first picks a base name where all three destinations are free (suffixing
    /// `_1`, `_2`, ... as `write` does for colliding captures) and only then moves. That means no
    /// `moveItem` here can collide, and nothing is ever deleted to make room. The companions are
    /// moved only if they exist, since a never-edited capture legitimately has neither.
    func renameCapture(rawURL: URL, toBaseName baseName: String) throws -> URL {
        guard let requested = FilenameGenerator.sanitizedBaseName(baseName) else {
            throw StorageError.invalidFilename(baseName)
        }
        let folder = rawURL.deletingLastPathComponent()
        let ext = rawURL.pathExtension.isEmpty ? "png" : rawURL.pathExtension
        let currentBase = rawURL.deletingPathExtension().lastPathComponent
        guard requested != currentBase else { return rawURL }

        let resolved = availableBaseName(requested, ext: ext, in: folder, ignoring: rawURL)
        let target = folder.appendingPathComponent("\(resolved).\(ext)")
        try FileManager.default.moveItem(at: rawURL, to: target)

        move(
            folder.appendingPathComponent(FilenameGenerator.editedName(fromRaw: rawURL.lastPathComponent)),
            to: folder.appendingPathComponent(FilenameGenerator.editedName(fromRaw: target.lastPathComponent))
        )
        move(annotationsURL(forRaw: rawURL), to: annotationsURL(forRaw: target))
        return target
    }

    /// Best-effort move used for a rename's companion files: they may simply not exist, and
    /// failing to move a sidecar should not strand the raw file under a half-applied rename.
    private func move(_ from: URL, to: URL) {
        guard FileManager.default.fileExists(atPath: from.path) else { return }
        do {
            try FileManager.default.moveItem(at: from, to: to)
        } catch {
            NSLog("Clipr: rename could not move \(from.lastPathComponent): \(error)")
        }
    }

    /// First base name whose raw, `_edited` and sidecar paths are all free. The capture's own
    /// current files are ignored, so a case-only rename ("shot" -> "Shot") isn't mistaken for a
    /// clash with itself on a case-insensitive volume.
    private func availableBaseName(_ base: String, ext: String, in folder: URL, ignoring rawURL: URL) -> String {
        let own = Set([
            rawURL.lastPathComponent,
            FilenameGenerator.editedName(fromRaw: rawURL.lastPathComponent),
            FilenameGenerator.annotationsName(fromRaw: rawURL.lastPathComponent)
        ].map { $0.lowercased() })

        func taken(_ candidate: String) -> Bool {
            let raw = "\(candidate).\(ext)"
            let names = [raw, FilenameGenerator.editedName(fromRaw: raw), FilenameGenerator.annotationsName(fromRaw: raw)]
            return names.contains { name in
                !own.contains(name.lowercased())
                    && FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path)
            }
        }

        guard taken(base) else { return base }
        var suffix = 1
        while taken("\(base)_\(suffix)") { suffix += 1 }
        return "\(base)_\(suffix)"
    }
}
