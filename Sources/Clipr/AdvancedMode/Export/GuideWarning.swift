import Foundation

/// Something that went wrong with one step but didn't stop the export.
enum GuideWarning: Equatable {
    case missingImage(step: Int)
    case damagedAnnotations(step: Int)
    case missingCloseUp(step: Int)

    /// The alert text listing affected steps, or nil when there's nothing to report.
    static func summary(_ warnings: [GuideWarning]) -> String? {
        let missing = warnings.compactMap { if case .missingImage(let step) = $0 { return step } else { return nil } }
        let damaged = warnings.compactMap { if case .damagedAnnotations(let step) = $0 { return step } else { return nil } }
        let closeUps = warnings.compactMap { if case .missingCloseUp(let step) = $0 { return step } else { return nil } }
        var lines: [String] = []
        if !missing.isEmpty { lines.append("\(stepList(missing)): image unavailable — exported with a placeholder.") }
        if !damaged.isEmpty { lines.append("\(stepList(damaged)): annotations couldn't be read — image left out to avoid exposing redacted content.") }
        if !closeUps.isEmpty { lines.append("\(stepList(closeUps)): close-up couldn't be rendered — exported without it.") }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func stepList(_ steps: [Int]) -> String {
        (steps.count == 1 ? "Step " : "Steps ") + steps.map(String.init).joined(separator: ", ")
    }
}
