import Foundation

struct FilenameGenerator {
    static func rawScreenshotName(date: Date, timeZone: TimeZone = .current) -> String {
        "Screenshot_\(timestamp(date: date, timeZone: timeZone)).png"
    }

    static func editedName(fromRaw rawFilename: String) -> String {
        guard rawFilename.hasSuffix(".png") else { return rawFilename + "_edited" }
        let base = String(rawFilename.dropLast(4))
        return "\(base)_edited.png"
    }

    /// Sidecar JSON filename storing a raw capture's live, editable `[AnnotationObject]` — see
    /// `StorageManager.saveAnnotations`/`loadAnnotations`. Kept alongside `_edited.png` (which is
    /// only a flattened preview/export) so reopening a previously-edited capture from Recents
    /// restores the actual annotation objects, not just a static image.
    static func annotationsName(fromRaw rawFilename: String) -> String {
        guard rawFilename.hasSuffix(".png") else { return rawFilename + "_annotations.json" }
        let base = String(rawFilename.dropLast(4))
        return "\(base)_annotations.json"
    }

    static func sessionFolderName(date: Date, timeZone: TimeZone = .current) -> String {
        "Session_\(timestamp(date: date, timeZone: timeZone))"
    }

    static func stepName(index: Int) -> String {
        String(format: "Step_%02d.png", index)
    }

    private static func timestamp(date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter.string(from: date)
    }
}
