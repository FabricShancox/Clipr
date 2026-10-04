import Foundation

/// How the HTML refers to step images: inline data URIs (one self-contained file, also what the
/// PDF and the clipboard use) or relative paths under `prefix`.
enum HTMLImageMode: Equatable {
    case embedded
    case linked(prefix: String)
}
