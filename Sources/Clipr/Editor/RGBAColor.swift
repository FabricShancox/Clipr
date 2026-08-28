import CoreGraphics

struct RGBAColor: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }

    /// How bright this colour reads to the eye, 0...1 — the classic per-channel weighting (green
    /// contributes far more perceived brightness than blue does).
    var perceivedLuminance: CGFloat { 0.299 * red + 0.587 * green + 0.114 * blue }

    /// Black or white, whichever stays legible painted on top of this colour — used for the digit
    /// on a numbered stamp's solid disc so the number adapts to the stamp's colour.
    ///
    /// The 0.6 cutoff is deliberately above the 0.5 midpoint: saturated mid-tones like the red and
    /// blue swatches land just either side of 0.5, and on a filled badge those read better with
    /// white on them, which a plain midpoint would not give. Alpha is carried over so a
    /// part-transparent stamp keeps a matching digit.
    var contrastingForeground: RGBAColor {
        perceivedLuminance > 0.6
            ? RGBAColor(red: 0, green: 0, blue: 0, alpha: alpha)
            : RGBAColor(red: 1, green: 1, blue: 1, alpha: alpha)
    }
}
