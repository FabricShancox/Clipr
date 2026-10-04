import Foundation
import CoreGraphics

/// How wide a step's image appears in the finished guide, as a share of the width available.
/// Stored per step so a small dialog needn't fill the page like a full-screen capture.
enum ImageSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large, full

    var id: String { rawValue }

    /// A size this build doesn't know (written by a newer Clipr) reads as Full rather than failing
    /// the whole manifest — which would open the session read-only over one cosmetic field.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ImageSize(rawValue: raw) ?? .full
    }

    var widthFraction: CGFloat {
        switch self {
        case .small: return 0.40
        case .medium: return 0.60
        case .large: return 0.80
        case .full: return 1.0
        }
    }
}
