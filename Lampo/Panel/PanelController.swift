import AppKit
import Observation
import SwiftUI

/// Drives the SwiftUI entrance animation.
@MainActor
@Observable
final class PanelPresentation {
    var isPresented = false
}

/// Shows, positions, resizes and hides the Glass panel.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let viewModel: PanelViewModel
    private let preferences: Preferences
    private let panel = LampoPanel()
    private let presentation = PanelPresentation()
    private var hostingView: NSHostingView<PanelView>?
    private var hideGeneration = 0
    private(set) var isVisible = false

    init(viewModel: PanelViewModel, preferences: Preferences) {
        self.viewModel = viewModel
        self.preferences = preferences
        super.init()

        let root = PanelView(
            viewModel: viewModel,
            presentation: presentation,
            onHeightChange: { [weak self] height in self?.updateHeight(height) },
            onClose: { [weak self] in self?.hide() }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        hostingView = hosting

        panel.delegate = self
        panel.keyDownHandler = { [weak self] event in self?.handleKeyDown(event) ?? false }
        viewModel.onRequestClose = { [weak self] in self?.hide() }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        hideGeneration += 1
        viewModel.panelWillAppear()
        let screen = Self.screenUnderMouse()
        let size = NSSize(width: fullWidth, height: max(panel.frame.height, 120))
        panel.setFrame(frame(for: size, on: screen), display: false)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        presentation.isPresented = reduceMotion
        panel.makeKeyAndOrderFront(nil)
        isVisible = true

        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            presentation.isPresented = true
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.05 : 0.14
            panel.animator().alphaValue = 1
        }
        Log.panel.debug("panel shown")
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        viewModel.cancel()
        hideGeneration += 1
        let generation = hideGeneration
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.05 : 0.1
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hideGeneration == generation else { return }
                self.panel.orderOut(nil)
                self.presentation.isPresented = false
            }
        }
        Log.panel.debug("panel hidden")
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // Click outside or another app took focus.
        hide()
    }

    // MARK: Keyboard

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if panel.activeTextView?.hasMarkedText() == true { return false }   // IME composition
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()

        if event.keyCode == 53 {   // Esc
            if viewModel.isGenerating {
                viewModel.cancel()
            } else {
                hide()
            }
            return true
        }
        guard modifiers == .command else { return false }
        switch key {
        case "c":
            let hasSelection = (panel.activeTextView?.selectedRange().length ?? 0) > 0
            guard !hasSelection, viewModel.canCopy else { return false }
            viewModel.copyCurrentAnswer()
            return true
        case "n":
            viewModel.resetConversation()
            return true
        case "w":
            hide()
            return true
        default:
            return false
        }
    }

    // MARK: Geometry

    private var fullWidth: CGFloat { DesignTokens.Panel.width + 2 * DesignTokens.Panel.shadowMargin }

    private func updateHeight(_ height: CGFloat) {
        guard height > 0 else { return }
        let screen = panel.screen ?? Self.screenUnderMouse()
        let maxHeight = screen.visibleFrame.height
        let newHeight = min(height, maxHeight)
        var frame = panel.frame
        guard abs(frame.height - newHeight) > 0.5 else { return }
        let top = frame.maxY
        frame.size.height = newHeight
        frame.origin.y = max(top - newHeight, screen.visibleFrame.minY)
        panel.setFrame(frame, display: true)
    }

    private func frame(for size: NSSize, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let margin = DesignTokens.Panel.shadowMargin
        var origin: NSPoint
        switch preferences.panelPosition {
        case .center:
            let glassTop = screen.frame.maxY - screen.frame.height * DesignTokens.Panel.topOffsetFraction
            origin = NSPoint(x: screen.frame.midX - size.width / 2, y: glassTop + margin - size.height)
        case .nearCursor:
            let mouse = NSEvent.mouseLocation
            origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - 12 + margin - size.height)
        }
        origin.x = min(max(origin.x, visible.minX - margin), visible.maxX - size.width + margin)
        origin.y = min(max(origin.y, visible.minY - margin), visible.maxY - size.height + margin)
        return NSRect(origin: origin, size: size)
    }

    static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
