import Foundation

/// Where an export is assembled, and how the finished output replaces what's at the destination.
extension GuideExporter {
    /// A folder to assemble the output in, and whether moving out of it is a same-volume rename.
    struct WorkFolder {
        let url: URL
        let onDestinationVolume: Bool
    }

    /// The system's replacement folder on the destination's volume; failing that (network and FAT
    /// drives), a hidden folder beside the destination — for Markdown, inside the chosen folder, which
    /// may itself be a volume's root; and only if that can't be made either, the system temp folder,
    /// from which `copyAcrossAndPlace` copies the output over before renaming it into place.
    func makeWorkFolder(for destination: URL, format: GuideFormat) throws -> WorkFolder {
        let fileManager = FileManager.default
        if let workRoot {
            let folder = workRoot.appendingPathComponent("ClipprExport-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            return WorkFolder(url: folder, onDestinationVolume: true)
        }
        if let folder = try? replacementDirectory(destination) {
            return WorkFolder(url: folder, onDestinationVolume: true)
        }
        let parent = format == .markdown ? destination : destination.deletingLastPathComponent()
        let sibling = parent.appendingPathComponent(Self.stagingPrefix + UUID().uuidString, isDirectory: true)
        if (try? fileManager.createDirectory(at: sibling, withIntermediateDirectories: false)) != nil {
            return WorkFolder(url: sibling, onDestinationVolume: true)
        }
        let folder = fileManager.temporaryDirectory.appendingPathComponent("ClipprExport-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return WorkFolder(url: folder, onDestinationVolume: false)
    }

    /// For output built on another volume: copies it to a hidden item beside the destination first,
    /// then renames that into place, so the destination's own name never holds a half-copied file.
    /// The hidden copy is always removed.
    nonisolated static func copyAcrossAndPlace(_ output: URL, format: GuideFormat, destination: URL) throws {
        let parent = format == .markdown ? destination : destination.deletingLastPathComponent()
        let staged = parent.appendingPathComponent(stagingPrefix + UUID().uuidString + (format == .markdown ? "" : "-" + destination.lastPathComponent))
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: output, to: staged)
        try moveIntoPlace(staged, format: format, destination: destination)
    }

    /// Replaces what's at the destination only now that the output is complete. For Markdown the
    /// destination is the chosen folder: the old `images/` is set aside while the new one moves in,
    /// and put back if guide.md then can't be placed, so a failed export leaves the folder as it was
    /// (an old guide.md never ends up beside new images, nor a new one beside missing images). If the
    /// old images can't be put back, they are left in the backup and the error says where.
    nonisolated static func moveIntoPlace(_ output: URL, format: GuideFormat, destination: URL,
                                          placeGuide: (URL, URL) throws -> Void = { try place($0, at: $1) },
                                          restoreImages: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }) throws {
        guard format == .markdown else { return try place(output, at: destination) }
        let fileManager = FileManager.default
        let imagesTarget = destination.appendingPathComponent(MarkdownGuideWriter.imagesFolder)
        let backup = destination.appendingPathComponent(".images-backup-\(UUID().uuidString)")
        let hadImages = fileManager.fileExists(atPath: imagesTarget.path)
        if hadImages { try fileManager.moveItem(at: imagesTarget, to: backup) }
        func restore() throws {
            guard hadImages else { return }
            do {
                try restoreImages(backup, imagesTarget)
            } catch {
                throw ImagesRestoreError(backup: backup)
            }
        }
        do {
            try fileManager.moveItem(at: output.appendingPathComponent(MarkdownGuideWriter.imagesFolder), to: imagesTarget)
        } catch {
            try restore()
            throw error
        }
        do {
            try placeGuide(output.appendingPathComponent(MarkdownGuideWriter.fileName),
                           destination.appendingPathComponent(MarkdownGuideWriter.fileName))
        } catch {
            try? fileManager.removeItem(at: imagesTarget)
            try restore()
            throw error
        }
        if hadImages { try? fileManager.removeItem(at: backup) }
    }

    nonisolated private static func place(_ item: URL, at target: URL) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: item)
        } else {
            try FileManager.default.moveItem(at: item, to: target)
        }
    }
}
