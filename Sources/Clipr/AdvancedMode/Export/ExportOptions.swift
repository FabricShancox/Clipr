import Foundation

/// What the export sheet chose. The title is per session; the rest is remembered by `SettingsStore`.
struct ExportOptions: Equatable {
    static let gifFrameRange: ClosedRange<Double> = 1...5

    var format: GuideFormat = .pdf
    var title: String
    var includeZoom = false
    var gifFrameSeconds: Double = 2
}
