import Foundation
import CoreGraphics

enum StampKind: String, CaseIterable, Codable {
    case check, cross, star
    case number1, number2, number3, number4, number5, number6, number7, number8, number9

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

enum AnnotationKind: Codable, Equatable {
    case rectangle
    case ellipse
    /// Explicit start/end points, not derived from `frame`: a `CGRect` is always normalized to
    /// a positive width/height, so reconstructing direction from `frame.minX/minY -> maxX/maxY`
    /// silently discards (or reverses) whichever diagonal the user actually dragged. Storing the
    /// real endpoints is what lets the arrowhead land on the end the user released, not always
    /// the geometrically-larger corner.
    case arrow(CGPoint, CGPoint)
    case freehand([CGPoint])
    case text(String, TextStyle)
    case highlighter
    case blur
    case stamp(StampKind)
}

struct TextStyle: Codable, Equatable {
    var fontSize: CGFloat
    var bold: Bool
    var italic: Bool

    static let `default` = TextStyle(fontSize: 18, bold: false, italic: false)
}

struct RGBAColor: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }
}

struct AnnotationObject: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: AnnotationKind
    var frame: CGRect
    var color: RGBAColor
    var strokeWidth: CGFloat

    /// Hit test with a small tolerance so thin stroke-only shapes (arrow, freehand) remain selectable.
    func contains(_ point: CGPoint) -> Bool {
        let tolerance: CGFloat = max(strokeWidth, 6)
        return frame.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    }
}
