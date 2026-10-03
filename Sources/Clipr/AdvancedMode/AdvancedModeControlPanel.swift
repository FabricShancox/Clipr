import Cocoa
import SwiftUI

/// Observable state the floating control panel renders — owned by `AdvancedModeControlPanel` and
/// updated by `AppDelegate` as steps land and the session pauses/resumes.
final class AdvancedModeControlState: ObservableObject {
    @Published var stepCount = 0
    @Published var isPaused = false
}

/// The small floating Pause/Stop bar shown while Advanced Mode runs. It never appears in a
/// step: steps capture only the clicked app's own window (`desktopIndependentWindow`), clicks on
/// it are ignored by `ClickCaptureManager`, and `sharingType = .none` keeps it out of other
/// screen recorders too.
final class AdvancedModeControlPanel: NSPanel {
    let state = AdvancedModeControlState()

    init(onTogglePause: @escaping () -> Void, onStop: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
            // Non-activating: clicking Pause/Stop must not make Clipr frontmost, or the click
            // would steal focus from the app the user is recording.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        sharingType = .none
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        let hosting = NSHostingView(rootView: AdvancedModeControlView(
            state: state, onTogglePause: onTogglePause, onStop: onStop
        ))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        contentView = hosting
        setContentSize(hosting.fittingSize)
        positionAtTopCenter()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func positionAtTopCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - frame.height - 12))
    }
}

private struct AdvancedModeControlView: View {
    @ObservedObject var state: AdvancedModeControlState
    let onTogglePause: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(state.isPaused ? Color.orange : Color.red)
                .frame(width: 8, height: 8)
            Text(state.isPaused ? "Paused · \(stepLabel)" : stepLabel)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .frame(minWidth: 70, alignment: .leading)
            Button(action: onTogglePause) {
                Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 20, height: 20)
            }
            .help(state.isPaused ? "Resume recording clicks" : "Pause — clicks won't be captured")
            Button(action: onStop) {
                Image(systemName: "stop.fill")
                    .foregroundColor(.red)
                    .frame(width: 20, height: 20)
            }
            .help("Stop and review captured steps")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        .fixedSize()
    }

    private var stepLabel: String { state.stepCount == 1 ? "1 step" : "\(state.stepCount) steps" }
}
