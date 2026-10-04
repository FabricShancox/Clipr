import Cocoa
import UniformTypeIdentifiers

/// Image formats "Save As…" can write. Captures themselves are always stored as PNG — lossless
/// and alpha-preserving, which matters for a canvas-resize that adds transparent space — so this
/// only applies to an explicit export the user asked for.
enum ExportFormat: String, CaseIterable {
    case png
    case jpeg

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    var bitmapType: NSBitmapImageRep.FileType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    /// JPEG has no alpha, so anything transparent (the area a canvas-resize added) would otherwise
    /// come out black. Callers composite onto white first when this is true.
    var needsOpaqueBackground: Bool {
        switch self {
        case .png: return false
        case .jpeg: return true
        }
    }

    var properties: [NSBitmapImageRep.PropertyKey: Any] {
        switch self {
        case .png: return [:]
        case .jpeg: return [.compressionFactor: 0.9]
        }
    }
}
