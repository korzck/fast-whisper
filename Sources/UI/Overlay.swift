import AppKit
import SwiftUI

/// Small transcript panel at the bottom right above the Dock.
/// NSPanel with .nonactivatingPanel preserves focus in the target application.
/// Mouse events pass through the panel (ignoresMouseEvents).
final class OverlayController {
    static let shared = OverlayController()
    static let size = NSSize(width: 400, height: 96)

    private var panel: NSPanel?

    func show() {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.hidesOnDeactivate = false
            p.contentView = NSHostingView(rootView: OverlayView(state: AppState.shared))
            panel = p
        }
        position()
        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
    }

    func hide(after delay: Double = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let p = self?.panel, AppState.shared.overlayPhase.isFinal else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                p.animator().alphaValue = 0
            }, completionHandler: {
                if AppState.shared.overlayPhase.isFinal {
                    p.orderOut(nil)
                    AppState.shared.overlayPhase = .hidden
                }
            })
        }
    }

    /// Bottom-right corner of the screen containing the pointer; visibleFrame excludes the Dock.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let f = screen?.visibleFrame, let p = panel else { return }
        p.setFrameOrigin(NSPoint(x: f.maxX - Self.size.width - 16, y: f.minY + 16))
    }
}

struct OverlayView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                indicator
                Text(state.overlayPhase.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if state.overlayPhase == .recording {
                    LevelMeter(level: state.level, active: true).frame(width: 60, height: 4)
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        overlayText
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Color.clear.frame(height: 1).id("end")
                    }
                }
                .onChange(of: state.partialText) { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end") } }
                .onChange(of: state.sessionVersion) { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("end") } }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(width: OverlayController.size.width, height: OverlayController.size.height, alignment: .topLeading)
        .background(VisualEffect().clipShape(RoundedRectangle(cornerRadius: 12)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12)))
    }

    private var overlayText: Text {
        let t = composeTranscript(state, session: state.session)
        return state.sessionIsEmpty ? Text(state.overlayPhase == .recording ? "Говорите…" : "").foregroundColor(.secondary) : t
    }

    @ViewBuilder private var indicator: some View {
        switch state.overlayPhase {
        case .recording: Circle().fill(Color.red).frame(width: 8, height: 8)
        case .finishing: ProgressView().controlSize(.mini)
        case .inserted: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 11))
        default: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).font(.system(size: 11))
        }
    }
}

/// Translucent system background, matching macOS HUD windows.
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// Render all segments or one session: italic for live speech, gray for raw
/// recognition, and normal color for LLM-corrected text.
