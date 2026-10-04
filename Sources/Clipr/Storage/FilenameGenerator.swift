import Foundation

struct FilenameGenerator {
    static func rawScreenshotName(date: Date, timeZone: TimeZone = .current) -> String {
        "Screenshot_\(timestamp(date: date, timeZone: timeZone)).png"
    }

    static func editedName(fromRaw rawFilename: String) -> String {
        companion(of: rawFilename, pngSuffix: "_edited.png", otherwise: "_edited")
    }

    /// Sidecar JSON filename storing a raw capture's live, editable `[AnnotationObject]` — see
    /// `StorageManager.saveAnnotations`/`loadAnnotations`. Kept alongside `_edited.png` (which is
    /// only a flattened preview/export) so reopening a previously-edited capture from Recents
    /// restores the actual annotation objects, not just a static image.
    static func annotationsName(fromRaw rawFilename: String) -> String {
        companion(of: rawFilename, pngSuffix: "_annotations.json", otherwise: "_annotations.json")
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

    /// The close-up crop saved next to a step when "Zoom on click" is on.
    static func zoomName(fromStep stepFilename: String) -> String {
        companion(of: stepFilename, pngSuffix: "_zoom.png", otherwise: "_zoom.png")
    }

    /// A raw step image in a session folder ("Step_03.png"), as opposed to the `_edited.png`
    /// preview and `_zoom.png` close-up written next to it.
    static func isRawStepName(_ name: String) -> Bool {
        name.hasPrefix("Step_") && name.lowercased().hasSuffix(".png")
            && !name.hasSuffix("_edited.png") && !name.hasSuffix("_zoom.png")
    }

    /// A file named off `filename`: its `.png` replaced by `pngSuffix`, or `otherwise` appended
    /// when it isn't a PNG.
    private static func companion(of filename: String, pngSuffix: String, otherwise: String) -> String {
        guard filename.hasSuffix(".png") else { return filename + otherwise }
        return filename.dropLast(4) + pngSuffix
    }

    private static func timestamp(date: Date, timeZone: TimeZone) -> String {
        DateFormats.string(date, pattern: "yyyy-MM-dd_HHmmss", timeZone: timeZone, gregorian: true)
    }
}
