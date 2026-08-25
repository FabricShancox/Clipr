import CoreGraphics

struct WindowInfo: Equatable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let bounds: CGRect
    let layer: Int
}
