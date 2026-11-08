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
    private let screenCapture: any ScreenCapturing
    private let routingPolicy: () -> RoutingPolicy
    private let lens: LensController
    private let hud: HUDController
    private weak var panel: PanelController?
    private var isBusy = false

    /// Called when an action needs a permission the user hasn't granted.
    var onNeedsPermission: ((PermissionKind) -> Void)?
    /// Called with each finished Lens, replace or copy result: action name, input, output, route.
    var onResult: ((String, String, String, ModelRoute) -> Void)?

    init(store: ActionStore, runner: ActionRunner, selectionReader: any SelectionReading, output: OutputService,
         permissions: any PermissionsChecking, pasteboard: any PasteboardClient,
         screenCapture: any ScreenCapturing, routingPolicy: @escaping () -> RoutingPolicy,
         lens: LensController, hud: HUDController, panel: PanelController?) {
        self.store = store
        self.runner = runner
        self.selectionReader = selectionReader
        self.output = output
        self.permissions = permissions
        self.pasteboard = pasteboard
        self.screenCapture = screenCapture
        self.routingPolicy = routingPolicy
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

        if let kind = action.output.draftKind {
            await runStructured(action, kind: kind)
            return
        }

        // Translations always work on the selected text.
        switch action.isTranslation ? .selection : action.input {
        case .selection:
            guard permissions.isAccessibilityGranted else {
                onNeedsPermission?(.accessibility)
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
            await openPanel(action, context: context, items: [])
        case .screen:
            await runOnScreen(action)
        }
    }

    /// "Create event" / "Create reminder": the selection becomes a draft card; with no selection
    /// (or no Accessibility) the panel asks for the description instead.
    private func runStructured(_ action: LampoAction, kind: DraftKind) async {
        var text: String?
        if action.input == .selection, permissions.isAccessibilityGranted {
            text = await selectionReader.readSelection(allowClipboardFallback: true)?.text
        } else if action.input == .clipboard {
            text = pasteboard.string()
        }
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            panel?.showDraft(kind, from: text)
        } else {
            panel?.showDraftInput(kind)
        }
    }

    /// "Ask the screen" and custom screen actions: capture the front window, then either wait
    /// for a question (empty template) or run the template on the screenshot.
    private func runOnScreen(_ action: LampoAction) async {
        guard permissions.isScreenRecordingGranted else {
            panel?.showNotice(.permission(.screenRecording))
            return
        }
        guard let app = SourceApp.frontmost() else {
            hud.show(ScreenCaptureError.noWindow.localizedDescription, style: .failure, near: nil)
            return
        }
        let capture: WindowCapture
        do {
            capture = try await screenCapture.captureFrontWindow(of: app)
        } catch {
            if (error as? ScreenCaptureError) == .permissionDenied {
                panel?.showNotice(.permission(.screenRecording))
            } else {
                let message = (error as? LocalizedError)?.errorDescription ?? ScreenCaptureError.failed.localizedDescription
                hud.show(message, style: .failure, near: nil)
            }
            return
        }
        if action.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            panel?.showScreenQuestion(capture)
        } else {
            let context = runner.templateContext(selection: nil, clipboard: nil, app: app.name)
            await openPanel(action, context: context, items: [.window(capture)])
        }
    }

    private func openPanel(_ action: LampoAction, context: TemplateContext, items: [ContextItem]) async {
        let images = items.contains { if case .window = $0 { true } else { false } } ? 1 : 0
        do {
            let prepared = try await runner.prepare(action, context: context, images: images)
            panel?.showRunning(action, prompt: prepared.prompt, wasTruncated: prepared.wasTruncated, contextItems: items)
        } catch {
            // Let the panel show the error in place, with the usual wording.
            panel?.showRunning(action, prompt: runner.prompt(for: action, context: context), contextItems: items)
        }
    }

    private func perform(_ action: LampoAction, on selection: SelectionContext) async {
        switch action.effectiveOutput {
        case .preview:
            let actions = store.selectionActions.filter { $0.effectiveOutput.showsInLens }
            let list = actions.contains { $0.id == action.id } ? actions : [action] + actions
            let lensModel = LensViewModel(selection: selection, actions: list, initialActionID: action.id,
                                          runner: runner, pasteboard: pasteboard, routingPolicy: routingPolicy())
            lensModel.onCompleted = { [weak self] action, result, route in
                self?.onResult?(action.name, selection.text, result, route)
            }
            lens.show(lensModel)
        case .openPanel:
            let context = runner.templateContext(selection: selection.text, clipboard: nil, app: selection.app?.name)
            await openPanel(action, context: context, items: [.selection(selection)])
        case .calendarEvent, .reminder:
            panel?.showDraft(action.output.draftKind ?? .event, from: selection.text)
        case .replaceSilently, .copy:
            hud.show(String(localized: "\(action.name)…"), style: .working, near: selection.anchor)
            do {
                let (text, wasTruncated, route) = try await complete(action, selection: selection)
                onResult?(action.name, selection.text, text, route)
                if action.effectiveOutput == .copy {
                    output.copy(text)
                    let message = wasTruncated ? String(localized: "Copied · Long text: used an excerpt") : String(localized: "Copied")
                    hud.show(message, style: .success, near: selection.anchor)
                } else {
                    await replace(text, in: selection, showHUD: true)
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? ModelError.other.localizedDescription
                hud.show(message, style: .failure, near: selection.anchor)
            }
        }
    }

    private func complete(_ action: LampoAction, selection: SelectionContext) async throws -> (String, Bool, ModelRoute) {
        let context = runner.templateContext(selection: selection.text, clipboard: nil, app: selection.app?.name)
        let run = try await runner.start(action, context: context)
        // Writing a rewrite of an excerpt over the whole selection would lose text.
        if run.wasTruncated && action.effectiveOutput == .replaceSilently { throw ModelError.tooLongToReplace }
        var last = ""
        for try await text in run.stream { last = text }
        let cleaned = action.isTranslation ? last : RewriteCleaner.clean(last, original: selection.text)
        guard !cleaned.isEmpty else { throw ModelError.emptyResponse }
        return (cleaned, run.wasTruncated, run.route)
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
