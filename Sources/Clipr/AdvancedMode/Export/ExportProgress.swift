import SwiftUI

/// How far the step images of a running export have rendered.
@MainActor
final class ExportProgress: ObservableObject {
    @Published var fraction: Double = 0
}
