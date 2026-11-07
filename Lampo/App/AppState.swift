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
    @ObservationIgnored let modelService: any ModelService
    @ObservationIgnored let hotkeys: HotkeyManager
    @ObservationIgnored private(set) var panelController: PanelController?
    @ObservationIgnored private(set) var actionCoordinator: ActionCoordinator?
    @ObservationIgnored private let onboarding = OnboardingWindowController()
    @ObservationIgnored let permissions: any PermissionsChecking = PermissionsService()
    private(set) var availability: ModelAvailability = .unknown
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    init(
        preferences: Preferences = Preferences(),
        actionStore: ActionStore? = nil,
        modelService: any ModelService = FoundationModelService(),
        hotkeyBackend: HotkeyBackend = KeyboardShortcutsBackend()
    ) {
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

        hotkeys.register(.togglePanel) { [weak self] in self?.togglePanel() }
        syncActionHotkeys()
        actionStore.onActionsAddedOrRemoved = { [weak self] in self?.syncActionHotkeys() }
        onboarding.showIfFirstLaunch(accessibilityGranted: permissions.isAccessibilityGranted)
        refreshAvailability()
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
        let names = actionStore.actions.map(\.shortcutName)
        hotkeys.sync(names, prefix: "action-") { [weak self] name in
            guard let self, self.isEnabled,
                  let action = self.actionStore.actions.first(where: { $0.shortcutName.rawValue == name.rawValue }) else { return }
            self.actionCoordinator?.perform(action.id)
        }
    }

    // MARK: Settings support

    /// A runner for the action editor's "Try" button.
    func makeRunner() -> ActionRunner {
        ActionRunner(model: modelService, preferences: preferences)
    }

    /// Every global shortcut, in Settings order: the panel first, then the actions.
    var shortcutNames: [(name: KeyboardShortcuts.Name, title: String)] {
        [(KeyboardShortcuts.Name.togglePanel, String(localized: "Open Lampo"))]
            + actionStore.actions.map { ($0.shortcutName, $0.name) }
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

    func togglePanel() {
        guard isEnabled else { return }
        refreshAvailability()
        panelController?.toggle()
    }
}
