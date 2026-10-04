import Foundation

/// One encoded image ready to embed or write out.
struct GuideImage: Equatable {
    enum Kind: Equatable { case png, jpeg }

    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let kind: Kind

    var mimeType: String { kind == .png ? "image/png" : "image/jpeg" }

    /// Positional names ("step-01.png", "step-01-zoom.jpg"), so an export never depends on how the
    /// session's own files happen to be named.
    static func fileName(step: Int, zoom: Bool, kind: Kind) -> String {
        String(format: "step-%02d", step) + (zoom ? "-zoom" : "") + (kind == .png ? ".png" : ".jpg")
    }
}
