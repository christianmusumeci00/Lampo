import AppIntents
import AppKit
import KeyboardShortcuts
import Observation

/// Root state shared by the menu bar, the panel and Settings.
@MainActor
@Observable
final class AppState {
    let preferences: Preferences
    let actionStore: ActionStore
    let history: HistoryStore
    let updates = UpdateController()
    @ObservationIgnored let modelService: any ModelService
    @ObservationIgnored let hotkeys: HotkeyManager
    @ObservationIgnored private let hotkeyBackend: HotkeyBackend
    @ObservationIgnored let dictationEngine: any DictationEngine
    @ObservationIgnored private(set) var dictation: DictationController?
    @ObservationIgnored private var dictationHUD: DictationHUDController?
    @ObservationIgnored private(set) var panelController: PanelController?
    @ObservationIgnored private(set) var actionCoordinator: ActionCoordinator?
    @ObservationIgnored private(set) var shortcuts: ShortcutsService?
    @ObservationIgnored private let onboarding = OnboardingWindowController()
    @ObservationIgnored private let welcome = WelcomeWindowController()
    @ObservationIgnored let permissions: any PermissionsChecking = PermissionsService()
    private(set) var availability: ModelAvailability = .unknown
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    init(
        preferences: Preferences = Preferences(),
        actionStore: ActionStore? = nil,
        modelService: any ModelService = FoundationModelService(),
        hotkeyBackend: HotkeyBackend = KeyboardShortcutsBackend(),
        dictationEngine: (any DictationEngine)? = nil
    ) {
        self.hotkeyBackend = hotkeyBackend
        self.dictationEngine = dictationEngine ?? SystemDictationEngine()
        self.preferences = preferences
        self.actionStore = actionStore ?? ActionStore()
        self.history = HistoryStore(isEnabled: { [preferences] in preferences.keepHistory })
        self.modelService = modelService
        self.hotkeys = HotkeyManager(backend: hotkeyBackend, isEnabled: preferences.isEnabled)
    }

    /// Lampo on/off. Off unregisters every hotkey and hides all UI.
    var isEnabled: Bool {
        get { preferences.isEnabled }
        set {
            preferences.isEnabled = newValue
            hotkeys.setEnabled(newValue)
            if !newValue { panelController?.hide() }
        }
    }

    var statusLine: String {
        isEnabled ? availability.shortStatus : String(localized: "Disabled")
    }

    func start() {
        let pasteboard = SystemPasteboard()
        let accessibility = SystemAccessibilityClient()
        let clipboard = ClipboardBridge(pasteboard: pasteboard, keystrokes: SystemKeystrokeSender())
        let selectionService = SelectionService(accessibility: accessibility, clipboard: clipboard)
        let output = OutputService(accessibility: accessibility, clipboard: clipboard, pasteboard: pasteboard)

        let screenCapture = ScreenCaptureService()
        let viewModel = PanelViewModel(model: modelService, preferences: preferences, pasteboard: pasteboard,
                                       screenCapture: screenCapture)
        let panel = PanelController(viewModel: viewModel, preferences: preferences, selectionReader: selectionService,
                                    output: output, permissions: permissions, pasteboard: pasteboard)
        panelController = panel
        viewModel.onTurnCompleted = { [history] turn in
            history.record(source: String(localized: "Panel"), input: turn.question, output: turn.answer, route: turn.route)
        }

        let coordinator = ActionCoordinator(
            store: actionStore, runner: ActionRunner(model: modelService, preferences: preferences),
            selectionReader: selectionService, output: output, permissions: permissions, pasteboard: pasteboard,
            screenCapture: screenCapture, routingPolicy: { [preferences] in preferences.routingPolicy },
            lens: LensController(), hud: HUDController(), panel: panel)
        coordinator.onNeedsPermission = { [weak self] _ in self?.onboarding.show() }
        coordinator.onResult = { [history] source, input, output, route in
            history.record(source: source, input: input, output: output, route: route)
        }
        actionCoordinator = coordinator

        let hudModel = DictationHUDModel()
        let dictationHUD = DictationHUDController(model: hudModel)
        let dictation = DictationController(
            engine: dictationEngine, runner: ActionRunner(model: modelService, preferences: preferences),
            output: output, permissions: permissions, hotkeys: hotkeyBackend, statusHUD: HUDController(),
            hud: hudModel, language: { [preferences] in preferences.dictationLanguageIdentifier })
        dictation.onShowHUD = { [dictationHUD] visible in dictationHUD.setVisible(visible) }
        dictation.onNeedsModel = { [weak self] in self?.offerDictationModel() }
        dictation.onOpenPanel = { [weak coordinator] action, context in
            Task { await coordinator?.openPanel(action, context: context, items: []) }
        }
        dictation.onShowDraft = { [weak panel] kind, text in panel?.showDraft(kind, from: text) }
        dictation.onResult = { [history] source, input, output, route in
            history.record(source: source, input: input, output: output, route: route)
        }
        coordinator.onDictate = { [weak dictation] action in dictation?.keyDown(action) }
        self.dictation = dictation
        self.dictationHUD = dictationHUD

        let shortcuts = ShortcutsService(model: modelService, preferences: preferences, actionStore: actionStore,
                                         history: history)
        shortcuts.showDraft = { [weak panel] kind, text in panel?.showDraft(kind, from: text) }
        self.shortcuts = shortcuts
        AppDependencyManager.shared.add(dependency: shortcuts)

        PanelShortcutMigration.run(taken: shortcutEntries.dropFirst().map(\.shortcut))
        hotkeys.register(.togglePanel) { [weak self] in self?.togglePanel() }
        syncActionHotkeys()
        actionStore.onActionsAddedOrRemoved = { [weak self] in self?.syncActionHotkeys() }
        refreshAvailability()
        welcome.showIfFirstLaunch(availability: availability)
        updates.start()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAvailability() }
        }
        Log.app.info("Lampo started; model \(String(describing: self.availability), privacy: .public)")
    }

    func refreshAvailability() {
        availability = modelService.availability()
    }

    /// Registers one global hotkey per action (call again after editing actions).
    func syncActionHotkeys() {
        let names = actionStore.enabledActions.map(\.shortcutName)
        hotkeys.sync(names, prefix: "action-", action: { [weak self] name in
            guard let self, self.isEnabled,
                  let action = self.actionStore.enabledActions.first(where: { $0.shortcutName.rawValue == name.rawValue }) else { return }
            self.actionCoordinator?.perform(action.id)
        }, keyUp: { [weak self] name in
            // Push-to-talk: releasing a dictation shortcut after a moment stops listening.
            guard let self, let action = self.actionStore.enabledActions.first(where: {
                $0.shortcutName.rawValue == name.rawValue
            }), action.isDictation else { return }
            self.dictation?.keyUp(action.id)
        })
    }

    // MARK: Settings support

    /// A runner for the action editor's "Try" button.
    func makeRunner() -> ActionRunner {
        ActionRunner(model: modelService, preferences: preferences)
    }

    /// Every global shortcut, in Settings order: the panel first, then the turned-on actions.
    var shortcutNames: [(name: KeyboardShortcuts.Name, title: String)] {
        [(KeyboardShortcuts.Name.togglePanel, String(localized: "Open Lampo"))]
            + actionStore.enabledActions.map { ($0.shortcutName, $0.name) }
    }

    /// Turns an action on or off. Turning one on drops its shortcut if another command uses it
    /// (e.g. Summarize's old ⌥⇧R, now Rewrite's).
    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard var action = actionStore.action(id: id), action.isEnabled != enabled else { return }
        if enabled, let shortcut = KeyboardShortcuts.getShortcut(for: action.shortcutName),
           shortcutEntries.contains(where: { $0.shortcut == shortcut }) {
            KeyboardShortcuts.setShortcut(nil, for: action.shortcutName)
        }
        action.isEnabled = enabled
        actionStore.update(action)
    }

    var shortcutEntries: [ShortcutConflicts.Entry] {
        shortcutNames.map { ShortcutConflicts.Entry(title: $0.title, shortcut: KeyboardShortcuts.getShortcut(for: $0.name)) }
    }

    /// Deletes an action and frees its shortcut.
    func deleteAction(_ id: UUID) {
        if let action = actionStore.action(id: id) {
            KeyboardShortcuts.setShortcut(nil, for: action.shortcutName)
        }
        actionStore.delete(id)
    }

    /// Restores the built-in actions; those left without a shortcut get their default back.
    func restoreBuiltInActions() {
        actionStore.restoreBuiltIns()
        let unassigned = BuiltInActions.all.map(\.shortcutName).filter { KeyboardShortcuts.getShortcut(for: $0) == nil }
        if !unassigned.isEmpty { KeyboardShortcuts.reset(unassigned) }
    }

    /// Resets the panel and every action shortcut to its default (none for custom actions).
    func restoreDefaultShortcuts() {
        KeyboardShortcuts.reset(shortcutNames.map(\.name))
    }

    func perform(_ action: LampoAction) {
        guard isEnabled else { return }
        actionCoordinator?.perform(action.id)
    }

    func showPermissions() {
        onboarding.show()
    }

    /// Handles a `lampo://` link.
    func open(_ url: URL) {
        guard let link = LampoURL(url) else {
            Log.app.info("ignored unknown link")
            return
        }
        guard isEnabled else { return }
        switch link {
        case .ask(let question):
            refreshAvailability()
            panelController?.showQuestion(question)
        }
    }

    func togglePanel() {
        guard isEnabled else { return }
        refreshAvailability()
        panelController?.toggle()
    }
}

extension AppState {
    /// The speech model for the dictation language isn't on this Mac: ask before downloading it
    /// from Apple (the only download Lampo starts, and only on this explicit yes).
    func offerDictationModel() {
        let language = TranslationPlanner.displayName(preferences.dictationLanguageIdentifier)
        let alert = NSAlert()
        alert.messageText = String(localized: "Download the \(language) dictation model?")
        alert.informativeText = String(localized: "Dictation runs on this Mac with Apple's speech model. It's downloaded once from Apple; what you say never leaves your Mac.")
        alert.addButton(withTitle: String(localized: "Download"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        downloadDictationModel()
    }

    func downloadDictationModel() {
        let language = preferences.dictationLanguageIdentifier
        let hud = HUDController()
        hud.show(String(localized: "Downloading the dictation model…"), style: .working, near: nil)
        Task { [dictationEngine] in
            do {
                try await dictationEngine.downloadModel(for: language)
                hud.show(String(localized: "Dictation is ready"), style: .success, near: nil)
            } catch {
                Log.app.error("dictation model download failed: \(error.localizedDescription, privacy: .public)")
                hud.show(String(localized: "The download didn't work. Try again later."), style: .failure, near: nil)
            }
        }
    }
}
