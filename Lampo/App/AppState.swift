import AppKit
import Observation

/// Root state shared by the menu bar, the panel and Settings.
@MainActor
@Observable
final class AppState {
    let preferences: Preferences
    @ObservationIgnored let modelService: any ModelService
    @ObservationIgnored let hotkeys: HotkeyManager
    @ObservationIgnored private(set) var panelController: PanelController?
    private(set) var availability: ModelAvailability = .unknown
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?

    init(
        preferences: Preferences = Preferences(),
        modelService: any ModelService = FoundationModelService(),
        hotkeyBackend: HotkeyBackend = KeyboardShortcutsBackend()
    ) {
        self.preferences = preferences
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
        let viewModel = PanelViewModel(model: modelService, preferences: preferences, pasteboard: SystemPasteboard())
        panelController = PanelController(viewModel: viewModel, preferences: preferences)
        hotkeys.register(.togglePanel) { [weak self] in self?.togglePanel() }
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

    func togglePanel() {
        guard isEnabled else { return }
        refreshAvailability()
        panelController?.toggle()
    }
}
