import Foundation

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
