import Cocoa

extension NSImage {
    /// Used by `AnnotationRenderer.drawStamp` to color an SF Symbol stamp with the annotation's
    /// chosen color, since `NSImage(systemSymbolName:)` renders as a plain template image.
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
