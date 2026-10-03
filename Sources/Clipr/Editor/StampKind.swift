import CoreGraphics
import Foundation

enum StampKind: Hashable, Codable {
    case check, cross, star
    /// A numbered step. Any positive number — the counter used to stop at 9.
    case numbered(Int)

    /// The digit a numbered stamp shows, or `nil` for the non-numeric stamps.
    ///
    /// Numbered stamps are drawn as a solid disc with the digit painted on top, so they need the
    /// value itself rather than a symbol name: the `"N.circle.fill"` SF Symbols knock the digit
    /// out of the disc as a transparent hole, which lets the underlying screenshot show through
    /// and makes the number hard to read over busy captures. `symbolName` still covers the
    /// non-numeric stamps, whose symbols have no such cutout.
    var number: Int? {
        if case .numbered(let n) = self { return n }
        return nil
    }

    // Stored as the same single string the old fixed `number1`…`number9` cases used as their raw
    // value ("check", "number3"), now with any number after "number", so every sidecar written
    // before keeps decoding unchanged.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "check": self = .check
        case "cross": self = .cross
        case "star": self = .star
        default:
            guard raw.hasPrefix("number"), let n = Int(raw.dropFirst("number".count)), n > 0 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown stamp \(raw)"))
            }
            self = .numbered(n)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .check: try container.encode("check")
        case .cross: try container.encode("cross")
        case .star: try container.encode("star")
        case .numbered(let n): try container.encode("number\(n)")
        }
    }

    /// Digit font size as a fraction of the disc's diameter. Shared by the on-screen
    /// (`AnnotationOverlayShape`) and flattened (`AnnotationRenderer`) renderers so a stamp looks
    /// the same in the editor as it does in the exported image.
    static let digitScale: CGFloat = 0.6

    /// `digitScale`, shrunk for two- and three-digit numbers so they still fit inside the disc.
    static func digitScale(for number: Int) -> CGFloat {
        switch String(number).count {
        case 1: return digitScale
        case 2: return digitScale * 0.78
        default: return digitScale * 0.6
        }
    }

    /// Stamp diameter for a stroke preset, so the toolbar's Thin/Medium/Thick also size stamps,
    /// which have no outline of their own. Medium (4) gives the original fixed 32pt.
    static func side(forStrokeWidth width: CGFloat) -> CGFloat {
        16 + width * 4
    }

    /// Symbol drawn on top of a solid disc, for the stamps that are a mark inside a circle.
    ///
    /// The bare glyph, not the `.circle.fill` variant: those knock the mark out of the disc as a
    /// transparent hole, exactly the problem the numbered stamps had — the capture shows through
    /// the mark and it becomes hard to read over anything busy. `star` is not here because it is a
    /// solid shape in its own right, with nothing cut out of it.
    var discGlyph: String? {
        switch self {
        case .check: return "checkmark"
        case .cross: return "xmark"
        case .star: return nil
        default: return nil
        }
    }

    /// Glyph size as a fraction of the disc's diameter. Smaller than `digitScale` because these
    /// marks are wider than a digit at the same nominal size.
    static let glyphScale: CGFloat = 0.52

    var symbolName: String {
        switch self {
        case .check: return "checkmark.circle.fill"
        case .cross: return "xmark.circle.fill"
        case .star: return "star.fill"
        // SF Symbols only has numbered circles up to 50.
        case .numbered(let n): return (0...50).contains(n) ? "\(n).circle.fill" : "number.circle.fill"
        }
    }
}
