import AppKit
import SwiftUI

/// Small, click-through status capsule for silent actions ("Done · ⌘Z to undo").
@MainActor
final class HUDController {
    enum Style {
        case working
        case success
        case failure
    }

    @MainActor
    @Observable
    final class Model {
        var text = ""
        var style: Style = .working
    }

    private let panel: NSPanel
    private let model = Model()
    private var hideTask: Task<Void, Never>?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 90),
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
        let hosting = NSHostingView(rootView: HUDView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func show(_ text: String, style: Style, near anchor: CGRect?) {
        hideTask?.cancel()
        model.text = text
        model.style = style
        position(near: anchor)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        }
        if style == .success || style == .failure {
            AccessibilityNotification.Announcement(text).post()
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(style == .failure ? 3.5 : 1.8))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            MainActor.assumeIsolated { if panel.alphaValue == 0 { panel.orderOut(nil) } }
        }
    }

    private func position(near anchor: CGRect?) {
        let size = panel.frame.size
        let rect = LensController.usableAnchor(anchor)
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? PanelController.screenUnderMouse()
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height + 20)
        let visible = screen.visibleFrame
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(origin)
    }
}

private struct HUDView: View {
    var model: HUDController.Model

    var body: some View {
        HStack(spacing: 8) {
            switch model.style {
            case .working: ProgressView().controlSize(.small)
            case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failure: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Text(model.text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .modifier(PanelSurface(cornerRadius: 18))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
