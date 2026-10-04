import CoreGraphics

struct TextStyle: Codable, Equatable {
    var fontSize: CGFloat
    var bold: Bool
    var italic: Bool
    /// On by default per user request — a text annotation with no border was hard to spot
    /// against a busy screenshot background.
    var border: Bool
    var horizontalAlign: TextHorizontalAlign
    var verticalAlign: TextVerticalAlign

    static let `default` = TextStyle(
        fontSize: 18, bold: false, italic: false, border: true, horizontalAlign: .left, verticalAlign: .top
    )
}
