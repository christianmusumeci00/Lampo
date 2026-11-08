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
    private let selectionReader: any SelectionReading
    private let output: OutputService
    private let permissions: any PermissionsChecking
    private let pasteboard: any PasteboardClient
    private var selectionTask: Task<Void, Never>?
    /// The app the user was in when the panel opened (⌘⇧S captures its window).
    private var sourceApp: SourceApp?
    private let panel = LampoPanel()
    private let presentation = PanelPresentation()
    private var hostingView: NSHostingView<PanelView>?
    private var hideGeneration = 0
    private var pendingHeight: CGFloat = 0
    private var isResizeScheduled = false
    private(set) var isVisible = false

    init(viewModel: PanelViewModel, preferences: Preferences, selectionReader: any SelectionReading,
         output: OutputService, permissions: any PermissionsChecking, pasteboard: any PasteboardClient) {
        self.viewModel = viewModel
        self.preferences = preferences
        self.selectionReader = selectionReader
        self.output = output
        self.permissions = permissions
        self.pasteboard = pasteboard
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
        viewModel.onInsert = { [weak self] text, selection in self?.insert(text, replacing: selection) }
        viewModel.onSystemPromptFinished = { [weak self] in
            guard let self, self.isVisible else { return }
            self.panel.makeKeyAndOrderFront(nil)
        }
        viewModel.onGrantPermission = { [weak self] kind in
            self?.hide()
            self?.permissions.grant(kind)
        }
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
            attachSelectionChip()
        }
    }

    /// Opens the panel and runs an action whose answer belongs here (e.g. "Explain").
    func showRunning(_ action: LampoAction, prompt: String, wasTruncated: Bool = false, contextItems: [ContextItem]) {
        show()
        viewModel.runAction(action, prompt: prompt, wasTruncated: wasTruncated, contextItems: contextItems)
    }

    /// "Ask the screen": opens the panel with the window chip, ready for a question.
    func showScreenQuestion(_ capture: WindowCapture) {
        show()
        sourceApp = capture.app
        viewModel.prepareScreenQuestion(capture)
    }

    /// "Create event"/"Create reminder" on a text: opens the confirmation card.
    func showDraft(_ kind: DraftKind, from text: String) {
        show()
        viewModel.startDraft(kind, from: text)
    }

    /// "Extract" on a text: a contact, a table or to-dos, in an editable card.
    func showExtraction(from text: String) {
        show()
        viewModel.startExtraction(from: text)
    }

    /// "Create event"/"Create reminder" without a selection: asks for a description.
    func showDraftInput(_ kind: DraftKind) {
        show()
        viewModel.enterDraftInput(kind)
    }

    /// `lampo://ask?q=…`: opens the panel and asks the question, with no context attached.
    func showQuestion(_ question: String?) {
        show()
        guard let question else { return }
        viewModel.resetConversation()
        viewModel.query = question
        viewModel.submit()
    }

    /// Opens the panel with an actionable message (e.g. a missing permission).
    func showNotice(_ notice: PanelNotice) {
        show()
        viewModel.showNotice(notice)
    }

    /// Adds a "Selection" chip when text is selected in the app underneath. Accessibility only:
    /// the ⌘C fallback would have to steal focus from the panel, and the panel must open instantly.
    private func attachSelectionChip() {
        selectionTask?.cancel()
        selectionTask = Task { [weak self] in
            guard let self, let selection = await self.selectionReader.readSelection(allowClipboardFallback: false),
                  self.isVisible, !Task.isCancelled else { return }
            if !self.viewModel.hasContent || self.viewModel.activeSelection?.text != selection.text {
                self.viewModel.addContext(.selection(selection))
            }
        }
    }

    private func insert(_ text: String, replacing selection: SelectionContext?) {
        let target = selection?.app ?? SourceApp.frontmost()
        hide()
        Task { [output] in
            try? await Task.sleep(for: .milliseconds(80))
            if let selection {
                await output.replaceSelection(text, in: selection)
            } else {
                await output.insert(text, into: target)
            }
        }
    }

    func show() {
        if !isVisible { sourceApp = SourceApp.frontmost() }
        hideGeneration += 1
        viewModel.panelWillAppear()
        viewModel.setAccessibilityGranted(permissions.isAccessibilityGranted)
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
        selectionTask?.cancel()
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
        // A Calendar/Reminders permission prompt takes focus: stay open behind it.
        guard !viewModel.isWaitingForSystemPrompt else { return }
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
        if event.keyCode == 51, modifiers.isEmpty || modifiers == .function {   // Backspace
            return viewModel.removeLastContextIfQueryEmpty()
        }
        if modifiers == .command, event.keyCode == 36 || event.keyCode == 76 {   // ⌘↩ Insert / Add
            if viewModel.draft != nil {
                viewModel.confirmDraft()
            } else if let extraction = viewModel.extraction {
                switch extraction.kind {
                case .contact: viewModel.saveContact()
                case .table: viewModel.copyTable()
                case .todos: break
                }
            } else {
                viewModel.insertCurrentAnswer()
            }
            return true
        }
        if modifiers == [.command, .shift], key == "s" {   // ⌘⇧S attach the window underneath
            viewModel.toggleWindow(from: sourceApp, permitted: permissions.isScreenRecordingGranted)
            return true
        }
        if modifiers == [.command, .shift], key == "v" {   // ⌘⇧V attach clipboard
            if let text = pasteboard.string(), !text.isEmpty { viewModel.addContext(.clipboard(text)) }
            return true
        }
        guard modifiers == .command else { return false }
        switch key {
        case "c":
            let hasSelection = (panel.activeTextView?.selectedRange().length ?? 0) > 0
            if !hasSelection, let extraction = viewModel.extraction, extraction.phase == .ready {
                switch extraction.kind {
                case .contact: viewModel.copyContact()
                case .table: viewModel.copyTable()
                case .todos: return false
                }
                return true
            }
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

    /// Resizes on the next run-loop turn, like the Lens: resizing inside SwiftUI's layout pass
    /// while AppKit-backed controls (the Extract picker) appear makes AppKit abort.
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
