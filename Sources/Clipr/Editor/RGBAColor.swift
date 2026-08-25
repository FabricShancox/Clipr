import CoreGraphics

struct RGBAColor: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }
}
