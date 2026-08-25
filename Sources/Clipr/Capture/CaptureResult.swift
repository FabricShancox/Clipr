import Cocoa

enum CaptureResult {
    case area(CGRect, NSScreen)
    case fullScreen(NSScreen)
    case window(WindowInfo)
    case cancelled
}
