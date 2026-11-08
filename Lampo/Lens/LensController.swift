import AppKit
import SwiftUI

/// Shows the Lens next to the selection, as a non-activating key panel.
@MainActor
final class LensController: NSObject, NSWindowDelegate {
    private let panel = LampoPanel()
    private let layout = LensLayout()
    private var viewModel: LensViewModel?
    private var anchor: CGRect = .zero
    private(set) var isVisible = false
    private var pendingHeight: CGFloat = 0
    private var isResizeScheduled = false

    /// Called after the Lens closes for a replacement, with the text and the selection.
    var onReplace: ((String, SelectionContext) -> Void)?

    override init() {
        super.init()
        panel.delegate = self
        panel.keyDownHandler = { [weak self] event in self?.handleKeyDown(event) ?? false }
        panel.setAccessibilityLabel(String(localized: "Lampo Lens"))
    }

    func show(_ viewModel: LensViewModel) {
        close()
        self.viewModel = viewModel
        viewModel.onReplace = { [weak self, weak viewModel] text in
            guard let self, let viewModel else { return }
            let selection = viewModel.selection
            self.close()
            self.onReplace?(text, selection)
        }

        anchor = Self.usableAnchor(viewModel.selection.anchor)
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? PanelController.screenUnderMouse()
        let margin = DesignTokens.Panel.shadowMargin
        let width = DesignTokens.Lens.width + 2 * margin
        let initialHeight: CGFloat = 230 + 2 * margin
        let visible = screen.visibleFrame

        // Below the selection when there is room, otherwise above.
        let gap: CGFloat = 4
        let spaceBelow = anchor.minY - visible.minY
        layout.arrowEdge = spaceBelow >= initialHeight - margin ? .top : .bottom
        var x = anchor.midX - width / 2
        x = min(max(x, visible.minX - margin + 8), visible.maxX - width + margin - 8)
        layout.arrowX = anchor.midX - (x + margin)

        let y: CGFloat = layout.arrowEdge == .top
            ? anchor.minY - gap + margin - initialHeight
            : anchor.maxY + gap - margin
        panel.setFrame(NSRect(x: x, y: y, width: width, height: initialHeight), display: false)
        Log.panel.info("lens anchor \(self.anchor.debugDescription, privacy: .public) frame \(self.panel.frame.debugDescription, privacy: .public)")

        let hosting = NSHostingView(rootView: LensView(
            viewModel: viewModel, layout: layout,
            onHeightChange: { [weak self] height in self?.updateHeight(height) },
            onClose: { [weak self] in self?.close() }))
        hosting.sizingOptions = []
        panel.contentView = hosting

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        isVisible = true
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.05 : 0.12
            panel.animator().alphaValue = 1
        }
        viewModel.start()
    }

    func close() {
        viewModel?.cancel()
        viewModel = nil
        guard isVisible else { return }
        isVisible = false
        panel.orderOut(nil)
        panel.contentView = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    /// Resizes on the next run-loop turn: resizing the window inside SwiftUI's layout pass, while
    /// AppKit-backed controls (the tone picker, the language menu) appear or disappear, makes AppKit
    /// throw "needs update constraints" during layout and abort.
    private func updateHeight(_ height: CGFloat) {
        pendingHeight = height
        guard !isResizeScheduled else { return }
        isResizeScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isResizeScheduled = false
                self.applyHeight(self.pendingHeight)
            }
        }
    }

    private func applyHeight(_ height: CGFloat) {
        guard height > 0, isVisible else { return }
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        if layout.arrowEdge == .top {
            let top = frame.maxY
            frame.size.height = height
            frame.origin.y = top - height
        } else {
            frame.size.height = height
        }
        panel.setFrame(frame, display: true)
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let viewModel else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53:  // Esc: cancel without touching anything
            close()
            return true
        case 48:  // Tab / ⇧Tab
            modifiers.contains(.shift) ? viewModel.previous() : viewModel.next()
            return true
        case 124:  // →
            viewModel.next()
            return true
        case 123:  // ←
            viewModel.previous()
            return true
        case 36, 76:  // Return, Enter
            viewModel.replace()
            return true
        default:
            break
        }
        if modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                viewModel.copy()
                return true
            case "r":
                viewModel.retry()
                return true
            default:
                break
            }
        }
        return false
    }

    /// Selection bounds when they look like a selection; otherwise a point at the pointer.
    static func usableAnchor(_ rect: CGRect?) -> CGRect {
        if let rect, rect.height > 0, rect.height < 220, NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) {
            return rect
        }
        let mouse = NSEvent.mouseLocation
        return CGRect(x: mouse.x, y: mouse.y - 10, width: 1, height: 20)
    }
}
