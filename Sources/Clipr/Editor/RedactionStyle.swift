import Foundation

/// How a `.blur` annotation hides what's under it.
enum RedactionStyle: String, Codable {
    /// Averages the covered area into coarse blocks. Reads as "hidden" while still hinting at the
    /// shape of what was there.
    case pixelate
    /// A flat opaque block. The only option that leaves nothing at all to recover — pixelated text
    /// can sometimes be reconstructed by someone who knows the font and rendering.
    case solid
}
