import Foundation

/// The Review window's three ways of showing steps. All three are rows of the same list, so
/// selection, reordering, delete and caption editing behave the same whichever is chosen.
enum ReviewLayout: String, CaseIterable, Identifiable {
    /// Small thumbnail beside the caption — the most steps on screen.
    case list
    /// Big image with the caption beside it — for checking what each step shows.
    case large
    /// Full-width image under its caption — reads like the finished guide.
    case guide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "List"
        case .large: return "Large"
        case .guide: return "Guide"
        }
    }

    var symbol: String {
        switch self {
        case .list: return "list.bullet"
        case .large: return "rectangle.split.2x1"
        case .guide: return "doc.richtext"
        }
    }
}
