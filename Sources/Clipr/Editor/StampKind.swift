import CoreGraphics
import Foundation

enum StampKind: String, CaseIterable, Codable {
    case check, cross, star
    case number1, number2, number3, number4, number5, number6, number7, number8, number9

    /// The digit a numbered stamp shows, or `nil` for the non-numeric stamps.
    ///
    /// Numbered stamps are drawn as a solid disc with the digit painted on top, so they need the
    /// value itself rather than a symbol name: the `"N.circle.fill"` SF Symbols knock the digit
    /// out of the disc as a transparent hole, which lets the underlying screenshot show through
    /// and makes the number hard to read over busy captures. `symbolName` still covers the
    /// non-numeric stamps, whose symbols have no such cutout.
    var number: Int? {
        switch self {
        case .check, .cross, .star: return nil
        case .number1: return 1
        case .number2: return 2
        case .number3: return 3
        case .number4: return 4
        case .number5: return 5
        case .number6: return 6
        case .number7: return 7
        case .number8: return 8
        case .number9: return 9
        }
    }

    /// Digit font size as a fraction of the disc's diameter. Shared by the on-screen
    /// (`AnnotationOverlayShape`) and flattened (`AnnotationRenderer`) renderers so a stamp looks
    /// the same in the editor as it does in the exported image.
    static let digitScale: CGFloat = 0.6

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
        case .number1: return "1.circle.fill"
        case .number2: return "2.circle.fill"
        case .number3: return "3.circle.fill"
        case .number4: return "4.circle.fill"
        case .number5: return "5.circle.fill"
        case .number6: return "6.circle.fill"
        case .number7: return "7.circle.fill"
        case .number8: return "8.circle.fill"
        case .number9: return "9.circle.fill"
        }
    }
}
