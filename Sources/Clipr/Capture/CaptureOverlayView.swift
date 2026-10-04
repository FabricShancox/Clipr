import SwiftUI

/// One screen's capture overlay: the frozen screen, dimmed, with the Area / Window / Full Screen
/// picker, the drag selection and the hovered-window outline.
struct CaptureOverlayView: View {
    let screen: NSScreen
    /// The screen as it was when the hotkey fired. Drawn under the dimming so that whatever the
    /// overlay's activation closed in the app below (an open dropdown or menu) still shows.
    let frozenImage: NSImage?
    let onResult: (CaptureResult) -> Void

    @State private var mode: CaptureMode = .area
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var hoveredWindow: WindowInfo?
    /// The on-screen windows, listed once per capture on the first hover in Window mode rather than
    /// with a `CGWindowListCopyWindowInfo` call on every mouse move. The screen is frozen for the
    /// capture anyway.
    @State private var windows: [WindowInfo]?

    var body: some View {
        ZStack(alignment: .top) {
            if let frozenImage {
                Image(nsImage: frozenImage)
                    .resizable()
            }
            Color.black.opacity(0.15)
            selectionOutline
            hoveredWindowOutline
            modePicker
        }
        // The whole overlay, not just the frozen image, ignores the safe area: drags are measured
        // in this stack's space and cropped in the screen's, so on a notched display a stack
        // inset by the notch put every crop off by the notch height.
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .gesture(areaDrag)
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
        .onContinuousHover { phase in updateHoveredWindow(phase) }
    }

    /// The area being dragged out, in Area mode.
    @ViewBuilder
    private var selectionOutline: some View {
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
    }

    /// The window under the pointer, in Window mode.
    @ViewBuilder
    private var hoveredWindowOutline: some View {
        if mode == .window, let hovered = hoveredWindow {
            // hovered.bounds is in CGWindowBounds' global-display space; convert back to this
            // view's local space before using it to position SwiftUI content (see the note on
            // globalDisplayPoint below - this is that conversion's inverse).
            let localOrigin = CaptureOverlayView.viewLocalPoint(forGlobalDisplayPoint: hovered.bounds.origin, on: screen)
            let localRect = CGRect(origin: localOrigin, size: hovered.bounds.size)
            Rectangle()
                .stroke(Color.accentColor, lineWidth: 3)
                .frame(width: localRect.width, height: localRect.height)
                .position(x: localRect.midX, y: localRect.midY)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 12) {
            ForEach(CaptureMode.allCases, id: \.self) { m in
                Button(m.rawValue) { mode = m }
                    .buttonStyle(.borderedProminent)
                    .tint(mode == m ? .accentColor : .gray)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        // Below the camera housing on a notched display, now that the whole overlay ignores
        // the safe area.
        .padding(.top, 24 + screen.safeAreaInsets.top)
    }

    private var areaDrag: some Gesture {
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
    }

    private func updateHoveredWindow(_ phase: HoverPhase) {
        guard mode == .window else { hoveredWindow = nil; return }
        switch phase {
        case .active(let location):
            let screenPoint = CaptureOverlayView.globalDisplayPoint(forViewLocalPoint: location, on: screen)
            let list = windows ?? WindowPicker.onScreenWindows()
            if windows == nil { windows = list }
            hoveredWindow = WindowPicker.window(at: screenPoint, in: list)
        case .ended:
            // Each display has its own overlay; leaving this one must clear its highlight, or a
            // stale outline stays on this screen while the pointer is on another.
            hoveredWindow = nil
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

    /// Inverse of `globalDisplayPoint(forViewLocalPoint:on:)`: converts a point already in the
    /// CG "global display" space (e.g. a `WindowInfo.bounds` origin from `WindowPicker`) back into
    /// this view's local coordinate space, so it can be used with SwiftUI positioning modifiers.
    static func viewLocalPoint(forGlobalDisplayPoint point: CGPoint, on screen: NSScreen) -> CGPoint {
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenTopLeftY = mainScreenHeight - screen.frame.maxY
        return CGPoint(
            x: point.x - screen.frame.origin.x,
            y: point.y - screenTopLeftY
        )
    }
}
