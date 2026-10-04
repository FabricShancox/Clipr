import Foundation

extension ImageSize {
    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .full: return "Full"
        }
    }

    var shortLabel: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        case .full: return "Full"
        }
    }
}
