import Foundation
import Observation

enum PanelPosition: String, CaseIterable, Sendable {
    case center
    case nearCursor
}

enum ResponseLanguage: String, CaseIterable, Sendable {
    case automatic
    case italian
    case english
}

/// User preferences, persisted in `UserDefaults`.
@MainActor
@Observable
final class Preferences {
    enum Key {
        static let isEnabled = "isEnabled"
        static let onlyOnMac = "onlyOnMac"
        static let closePanelAfterCopy = "closePanelAfterCopy"
        static let panelPosition = "panelPosition"
        static let responseLanguage = "responseLanguage"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.isEnabled) } }
    var onlyOnMac: Bool { didSet { defaults.set(onlyOnMac, forKey: Key.onlyOnMac) } }
    var closePanelAfterCopy: Bool { didSet { defaults.set(closePanelAfterCopy, forKey: Key.closePanelAfterCopy) } }
    var panelPosition: PanelPosition { didSet { defaults.set(panelPosition.rawValue, forKey: Key.panelPosition) } }
    var responseLanguage: ResponseLanguage { didSet { defaults.set(responseLanguage.rawValue, forKey: Key.responseLanguage) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.onlyOnMac: false,
            Key.closePanelAfterCopy: false,
        ])
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        onlyOnMac = defaults.bool(forKey: Key.onlyOnMac)
        closePanelAfterCopy = defaults.bool(forKey: Key.closePanelAfterCopy)
        panelPosition = defaults.string(forKey: Key.panelPosition).flatMap(PanelPosition.init(rawValue:)) ?? .center
        responseLanguage = defaults.string(forKey: Key.responseLanguage).flatMap(ResponseLanguage.init(rawValue:)) ?? .automatic
    }

    var routingPolicy: RoutingPolicy { RoutingPolicy(onlyOnMac: onlyOnMac) }
}
