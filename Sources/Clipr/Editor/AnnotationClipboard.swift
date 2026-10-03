import Cocoa

/// Copying annotations (not the image) so they can be pasted back into this capture or another
/// one. Carried on the system pasteboard under a private type, so it works across editor windows
/// and survives switching captures.
struct AnnotationClipboard: Codable, Equatable {
    static let pasteboardType = NSPasteboard.PasteboardType("app.clipr.annotations")

    /// Height of the canvas they were copied from. Annotation geometry is stored bottom-left
    /// origin, so pasting into a capture of a different height needs this to keep each one the
    /// same distance from the TOP, where the user would expect it.
    var canvasHeight: CGFloat
    var annotations: [AnnotationObject]

    /// Offset applied each time a paste would land exactly on top of what's already there, so
    /// repeated pastes walk a visible trail. Renderer space, so down-right on screen is -y.
    static let pasteOffset = CGPoint(x: 12, y: -12)

    func write(to pasteboard: NSPasteboard = .general) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        pasteboard.clearContents()
        pasteboard.setData(data, forType: Self.pasteboardType)
    }

    static func read(from pasteboard: NSPasteboard = .general) -> AnnotationClipboard? {
        guard let data = pasteboard.data(forType: pasteboardType) else { return nil }
        return try? JSONDecoder().decode(AnnotationClipboard.self, from: data)
    }

    /// The annotations to insert into a canvas of `canvasSize` that already holds `existing`:
    /// fresh ids, kept the same distance from the top, nudged off any exact copies already there,
    /// and pulled back into view if they'd otherwise land entirely off a smaller capture.
    func annotationsForPaste(into canvasSize: CGSize, existing: [AnnotationObject]) -> [AnnotationObject] {
        let lift = CGPoint(x: 0, y: canvasSize.height - canvasHeight)
        var pasted = annotations.map { $0.translated(by: lift).withNewID() }

        func overlapsExisting() -> Bool {
            pasted.contains { p in existing.contains { $0.kind == p.kind && $0.frame == p.frame } }
        }
        var attempts = 0
        while overlapsExisting(), attempts < 50 {
            pasted = pasted.map { $0.translated(by: Self.pasteOffset) }
            attempts += 1
        }

        let bounds = CGRect(origin: .zero, size: canvasSize)
        let union = pasted.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        if !union.isNull, !union.intersects(bounds) {
            // Top-left of the group to just inside the top-left of the canvas.
            let target = CGPoint(x: 12, y: canvasSize.height - 12 - union.height)
            let delta = CGPoint(x: target.x - union.minX, y: target.y - union.minY)
            pasted = pasted.map { $0.translated(by: delta) }
        }
        return pasted
    }
}

extension AnnotationObject {
    /// A copy with its own identity. `id` is a `let`, and a copy must not share the original's
    /// identity or `ForEach` and the selection would confuse the two.
    func withNewID() -> AnnotationObject {
        AnnotationObject(
            id: UUID(), kind: kind, frame: frame,
            color: color, strokeWidth: strokeWidth, redactionStyle: redactionStyle
        )
    }
}
