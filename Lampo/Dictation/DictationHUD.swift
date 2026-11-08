import AppKit
import KeyboardShortcuts
import SwiftUI

/// What the listening capsule shows.
@MainActor
@Observable
final class DictationHUDModel {
    enum Phase: Equatable {
        case idle
        case listening
        case finishing
    }

    var phase: Phase = .idle
    var transcript = ""
    /// Microphone level, 0…1.
    var level: Float = 0
    /// The action's shortcut ("⌥⇧D"), shown in the hint.
    var shortcut: String?

    func reset(shortcut: String?) {
        phase = .idle
        transcript = ""
        level = 0
        self.shortcut = shortcut
    }
}

/// Click-through capsule at the bottom of the screen while Lampo listens. It never takes focus,
/// so the app being dictated into stays frontmost.
@MainActor
final class DictationHUDController {
    private let panel: NSPanel
    let model: DictationHUDModel

    init(model: DictationHUDModel) {
        self.model = model
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: DesignTokens.Dictation.width, height: 120),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.setAccessibilityLabel(String(localized: "Lampo is listening"))
        let hosting = NSHostingView(rootView: DictationHUDView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func setVisible(_ visible: Bool) {
        if visible {
            let screen = PanelController.screenUnderMouse().visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2,
                                         y: screen.minY + DesignTokens.Dictation.bottomOffset))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
            AccessibilityNotification.Announcement(String(localized: "Lampo is listening")).post()
        } else {
            panel.orderOut(nil)
        }
    }
}

private struct DictationHUDView: View {
    var model: DictationHUDModel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DesignTokens.accent.opacity(0.25))
                    .frame(width: 34, height: 34)
                    .scaleEffect(model.phase == .listening ? 1 + CGFloat(model.level) * 0.45 : 1)
                    .animation(.easeOut(duration: 0.1), value: model.level)
                Circle()
                    .fill(DesignTokens.accent)
                    .frame(width: 30, height: 30)
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Group {
                    if model.phase == .finishing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Tidying up…")
                        }
                    } else if model.transcript.isEmpty {
                        Text("Listening…").foregroundStyle(.secondary)
                    } else {
                        Text(model.transcript)
                            .lineLimit(2)
                            .truncationMode(.head)
                    }
                }
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)

                if model.phase == .listening {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .modifier(PanelSurface(cornerRadius: 22))
        .padding(DesignTokens.Dictation.shadowMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var hint: String {
        if let shortcut = model.shortcut {
            return String(localized: "Release or press \(shortcut) to finish · esc to cancel")
        }
        return String(localized: "esc to cancel")
    }
}
