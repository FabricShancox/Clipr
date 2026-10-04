import Foundation

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
        return (resulting as URL?) ?? url
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

    /// All-or-nothing: if any trashed file is gone (the Trash was emptied) nothing is moved back,
    /// so a restored manifest entry never points at a missing image.
    func restore(_ trashed: TrashedStep) throws {
        for move in trashed.moves where !FileManager.default.fileExists(atPath: move.trashed.path) {
            throw StepFilesError.trashedFileMissing(trashed.file)
        }
        for move in trashed.moves {
            try moveItem(move.trashed, move.original)
        }
    }
}
