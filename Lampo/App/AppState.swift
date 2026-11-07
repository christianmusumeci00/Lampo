import AppKit
import Observation

/// Root state shared by the menu bar, the panel and Settings.
@MainActor
@Observable
final class AppState {
    let preferences: Preferences
    let actionStore: ActionStore
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

        let viewModel = PanelViewModel(model: modelService, preferences: preferences, pasteboard: pasteboard)
        let panel = PanelController(viewModel: viewModel, preferences: preferences, selectionReader: selectionService,
                                    output: output, permissions: permissions, pasteboard: pasteboard)
        panelController = panel

        let coordinator = ActionCoordinator(
            store: actionStore, runner: ActionRunner(model: modelService, preferences: preferences),
            selectionReader: selectionService, output: output, permissions: permissions, pasteboard: pasteboard,
            lens: LensController(), hud: HUDController(), panel: panel)
        coordinator.onNeedsAccessibility = { [weak self] in self?.onboarding.show() }
        actionCoordinator = coordinator

        hotkeys.register(.togglePanel) { [weak self] in self?.togglePanel() }
        syncActionHotkeys()
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
