import SwiftUI

@MainActor
/// How far the step images of a running export have rendered.
final class ExportProgress: ObservableObject {
    @Published var fraction: Double = 0
}
