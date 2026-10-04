import AppKit

enum StepFilesError: Error, Equatable {
    case trashedFileMissing(String)
}

/// Where a step's files went when it was deleted, so undo can move them back.
struct TrashedStep: Equatable {
    struct Move: Equatable {
        let original: URL
        let trashed: URL
    }
    let file: String
    let moves: [Move]
}

/// Every file that belongs to one step, and moving them to and from the Trash together. The file
/// operations are injected so tests never touch the user's real Trash.
struct StepFiles {
    var trashItem: (URL) throws -> URL
    var moveItem: (URL, URL) throws -> Void

    init(
        trashItem: @escaping (URL) throws -> URL = StepFiles.liveTrash,
        moveItem: @escaping (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    ) {
        self.trashItem = trashItem
        self.moveItem = moveItem
    }

    static func liveTrash(_ url: URL) throws -> URL {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        guard let result = resulting as URL? else {
            // If the Trash operation succeeded but resultingItemURL is nil, we can't undo this move,
            // so we must fail rather than return a fabricated URL that undo might restore incorrectly.
            throw CocoaError(.fileNoSuchFile)
        }
        return result
    }

    /// The raw PNG first, then whichever of its sidecar, zoom crop and edited preview exist.
    static func companions(of file: String, in folder: URL) -> [URL] {
        let names = [
            file,
            FilenameGenerator.annotationsName(fromRaw: file),
            FilenameGenerator.zoomName(fromStep: file),
            FilenameGenerator.editedName(fromRaw: file),
        ]
        return names
            .map { folder.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The edited preview when there is one, so annotations added in the editor show in Review.
    static func thumbnailURL(of file: String, in folder: URL) -> URL {
        let edited = folder.appendingPathComponent(FilenameGenerator.editedName(fromRaw: file))
        return FileManager.default.fileExists(atPath: edited.path) ? edited : folder.appendingPathComponent(file)
    }

    /// The raw PNG must move or the whole step stays put (a step without its image would be a
    /// manifest entry pointing at nothing). Companions are best-effort: one stuck sidecar must not
    /// block deleting the step.
    func trash(_ file: String, in folder: URL) throws -> TrashedStep {
        let urls = Self.companions(of: file, in: folder)
        guard let raw = urls.first, raw.lastPathComponent == file else {
            throw CocoaError(.fileNoSuchFile)
        }
        var moves = [TrashedStep.Move(original: raw, trashed: try trashItem(raw))]
        for url in urls.dropFirst() {
            if let trashed = try? trashItem(url) {
                moves.append(TrashedStep.Move(original: url, trashed: trashed))
            }
        }
        return TrashedStep(file: file, moves: moves)
    }

    /// All-or-nothing: if any trashed file is gone (the Trash was emptied), nothing is moved back.
    /// If a moveItem fails mid-restore, all already-restored files are moved back to the Trash
    /// (best-effort) so a restored manifest entry never points at a partially-restored step.
    func restore(_ trashed: TrashedStep) throws {
        for move in trashed.moves where !FileManager.default.fileExists(atPath: move.trashed.path) {
            throw StepFilesError.trashedFileMissing(trashed.file)
        }
        var restoredMoves: [TrashedStep.Move] = []
        do {
            for move in trashed.moves {
                try moveItem(move.trashed, move.original)
                restoredMoves.append(move)
            }
        } catch {
            // Restore failed: move already-restored files back to Trash (best-effort, reverse order).
            for move in restoredMoves.reversed() {
                try? moveItem(move.original, move.trashed)
            }
            throw error
        }
    }

    /// A replacement step image, written as PNG at its own point size so Retina images keep every
    /// pixel (the same convention as capture: see `NSImage+PixelScale.swift`).
    static func writePNG(_ image: NSImage, to url: URL) throws {
        guard let bitmap = image.bitmap else { throw CocoaError(.fileWriteUnknown) }
        let rep = NSBitmapImageRep(cgImage: bitmap)
        rep.size = image.size
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
    }
}
