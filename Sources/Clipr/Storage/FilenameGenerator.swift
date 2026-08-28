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

    /// Cleans a user-typed capture name into something safe to write to disk, or `nil` if nothing
    /// usable survives. Used by the editor's click-the-filename rename.
    ///
    /// Path separators and `:` are folded to `-` rather than rejected, so an ordinary name like
    /// "Login 3/4" still works instead of erroring; the point is that a typed name can never
    /// traverse out of its folder. A leading `.` is dropped so a rename can't hide the capture,
    /// and a typed `.png` is stripped so the extension the caller appends isn't doubled up.
    static func sanitizedBaseName(_ input: String) -> String? {
        var name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasSuffix(".png") {
            name = String(name.dropLast(4))
        }
        name = String(name.map { character in
            character == "/" || character == ":" || character == "\\" ? "-" : character
        })
        name.removeAll { $0.isNewline || $0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } }
        while name.hasPrefix(".") { name.removeFirst() }
        name = name.trimmingCharacters(in: .whitespaces)

        // 200 leaves room for the `_annotations.json` suffix the sidecar adds within the 255-byte
        // limit almost every filesystem imposes on a single path component.
        guard !name.isEmpty, name.count <= 200 else { return nil }
        return name
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
