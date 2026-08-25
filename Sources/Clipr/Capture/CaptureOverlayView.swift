import SwiftUI

enum CaptureMode: String, CaseIterable {
    case area = "Area"
    case fullScreen = "Full Screen"
    case window = "Window"
}

enum CaptureResult {
    case area(CGRect, NSScreen)
    case fullScreen(NSScreen)
    case window(WindowInfo)
    case cancelled
}

struct CaptureOverlayView: View {
    let screen: NSScreen
    let onResult: (CaptureResult) -> Void

    @State private var mode: CaptureMode = .area
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var hoveredWindow: WindowInfo?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.15)

            if mode == .area, let start = dragStart, let current = dragCurrent {
                let rect = CGRect(
                    x: min(start.x, current.x), y: min(start.y, current.y),
                    width: abs(current.x - start.x), height: abs(current.y - start.y)
                )
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.1))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }

            if mode == .window, let hovered = hoveredWindow {
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 3)
                    .frame(width: hovered.bounds.width, height: hovered.bounds.height)
                    .position(x: hovered.bounds.midX, y: hovered.bounds.midY)
            }

            HStack(spacing: 12) {
                ForEach(CaptureMode.allCases, id: \.self) { m in
                    Button(m.rawValue) { mode = m }
                        .buttonStyle(.borderedProminent)
                        .tint(mode == m ? .accentColor : .gray)
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(.top, 24)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    guard mode == .area else { return }
                    if dragStart == nil { dragStart = value.startLocation }
                    dragCurrent = value.location
                }
                .onEnded { value in
                    guard mode == .area, let start = dragStart else { return }
                    let rect = CGRect(
                        x: min(start.x, value.location.x), y: min(start.y, value.location.y),
                        width: abs(value.location.x - start.x), height: abs(value.location.y - start.y)
                    )
                    dragStart = nil
                    dragCurrent = nil
                    if rect.width > 2 && rect.height > 2 {
                        onResult(.area(rect, screen))
                    }
                }
        )
        .onTapGesture { _ in
            switch mode {
            case .fullScreen:
                onResult(.fullScreen(screen))
            case .window:
                if let hovered = hoveredWindow {
                    onResult(.window(hovered))
                }
            case .area:
                break
            }
        }
        .onContinuousHover { phase in
            guard mode == .window else { hoveredWindow = nil; return }
            if case .active(let location) = phase {
                let screenPoint = CaptureOverlayView.globalDisplayPoint(forViewLocalPoint: location, on: screen)
                hoveredWindow = WindowPicker.window(at: screenPoint, in: WindowPicker.onScreenWindows())
            }
        }
    }

    /// Converts a point in this view's local coordinate space (SwiftUI convention: origin at the
    /// view's top-left, y increasing downward; the view fills `screen.frame` in points) into the
    /// coordinate space used by `CGWindowListCopyWindowInfo`'s `kCGWindowBounds` (and consumed by
    /// `WindowPicker.window(at:in:)`): the CoreGraphics "global display" space, whose origin is the
    /// top-left of the main display (the screen containing the menu bar), with y increasing downward.
    ///
    /// This is deliberately NOT `CGPoint(x: location.x, y: screen.frame.height - location.y)` (a
    /// naive flip): that formula actually converts into Cocoa's *global screen* space (bottom-left
    /// origin, y-up), the opposite of what `kCGWindowBounds` uses, and it also ignores
    /// `screen.frame.origin`, which is wrong on any multi-monitor setup where this screen isn't the
    /// primary display.
    static func globalDisplayPoint(forViewLocalPoint location: CGPoint, on screen: NSScreen) -> CGPoint {
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        // Y-coordinate of this screen's top-left corner, expressed in the y-down "global display" space.
        let screenTopLeftY = mainScreenHeight - screen.frame.maxY
        return CGPoint(
            x: screen.frame.origin.x + location.x,
            y: screenTopLeftY + location.y
        )
    }
}
