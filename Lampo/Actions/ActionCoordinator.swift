import AppKit

/// Runs an action from its hotkey or the Quick Actions menu:
/// read the selection, then preview (Lens), replace silently, copy, or open the panel.
@MainActor
final class ActionCoordinator {
    private let store: ActionStore
    private let runner: ActionRunner
    private let selectionReader: any SelectionReading
    private let output: OutputService
    private let permissions: any PermissionsChecking
    private let pasteboard: any PasteboardClient
    private let lens: LensController
    private let hud: HUDController
    private weak var panel: PanelController?
    private var isBusy = false

    /// Called when an action needs a permission the user hasn't granted.
    var onNeedsAccessibility: (() -> Void)?

    init(store: ActionStore, runner: ActionRunner, selectionReader: any SelectionReading, output: OutputService,
         permissions: any PermissionsChecking, pasteboard: any PasteboardClient, lens: LensController,
         hud: HUDController, panel: PanelController?) {
        self.store = store
        self.runner = runner
        self.selectionReader = selectionReader
        self.output = output
        self.permissions = permissions
        self.pasteboard = pasteboard
        self.lens = lens
        self.hud = hud
        self.panel = panel

        lens.onReplace = { [weak self] text, selection in
            guard let self else { return }
            Task { await self.replace(text, in: selection, showHUD: false) }
        }
    }

    func perform(_ actionID: UUID) {
        guard !isBusy, let action = store.action(id: actionID) else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            await run(action)
        }
    }

    private func run(_ action: LampoAction) async {
        panel?.hide()
        lens.close()

        switch action.input {
        case .selection:
            guard permissions.isAccessibilityGranted else {
                onNeedsAccessibility?()
                return
            }
            guard let selection = await selectionReader.readSelection(allowClipboardFallback: true) else {
                hud.show(String(localized: "Select some text first, then try again."), style: .failure, near: nil)
                return
            }
            await perform(action, on: selection)
        case .clipboard, .none:
            let clipboard = action.input == .clipboard ? pasteboard.string() : nil
            let context = runner.templateContext(selection: nil, clipboard: clipboard, app: SourceApp.frontmost()?.name)
            panel?.showRunning(action, prompt: runner.prompt(for: action, context: context), contextItems: [])
        case .screen:
            hud.show(String(localized: "Screen actions arrive in a later version."), style: .failure, near: nil)
        }
    }

    private func perform(_ action: LampoAction, on selection: SelectionContext) async {
        switch action.output {
        case .preview:
            let actions = store.selectionActions.filter { $0.output != .openPanel }
            let list = actions.contains { $0.id == action.id } ? actions : [action] + actions
            lens.show(LensViewModel(selection: selection, actions: list, initialActionID: action.id,
                                    runner: runner, pasteboard: pasteboard))
        case .openPanel:
            let context = runner.templateContext(selection: selection.text, clipboard: nil, app: selection.app?.name)
            panel?.showRunning(action, prompt: runner.prompt(for: action, context: context),
                               contextItems: [.selection(selection)])
        case .replaceSilently, .copy:
            hud.show(String(localized: "\(action.name)…"), style: .working, near: selection.anchor)
            do {
                let text = try await complete(action, selection: selection)
                if action.output == .copy {
                    output.copy(text)
                    hud.show(String(localized: "Copied"), style: .success, near: selection.anchor)
                } else {
                    await replace(text, in: selection, showHUD: true)
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? ModelError.other.localizedDescription
                hud.show(message, style: .failure, near: selection.anchor)
            }
        }
    }

    private func complete(_ action: LampoAction, selection: SelectionContext) async throws -> String {
        let context = runner.templateContext(selection: selection.text, clipboard: nil, app: selection.app?.name)
        let run = try runner.start(action, context: context)
        var last = ""
        for try await text in run.stream { last = text }
        let cleaned = RewriteCleaner.clean(last, original: selection.text)
        guard !cleaned.isEmpty else { throw ModelError.emptyResponse }
        return cleaned
    }

    private func replace(_ text: String, in selection: SelectionContext, showHUD: Bool) async {
        // Let the Lens/HUD give keyboard focus back to the source app.
        try? await Task.sleep(for: .milliseconds(60))
        await output.replaceSelection(text, in: selection)
        if showHUD {
            hud.show(String(localized: "Done · ⌘Z to undo"), style: .success, near: selection.anchor)
        }
    }
}
