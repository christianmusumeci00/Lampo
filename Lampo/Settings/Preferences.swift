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
        static let keepHistory = "keepHistory"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.isEnabled) } }
    var onlyOnMac: Bool { didSet { defaults.set(onlyOnMac, forKey: Key.onlyOnMac) } }
    var closePanelAfterCopy: Bool { didSet { defaults.set(closePanelAfterCopy, forKey: Key.closePanelAfterCopy) } }
    var panelPosition: PanelPosition { didSet { defaults.set(panelPosition.rawValue, forKey: Key.panelPosition) } }
    var responseLanguage: ResponseLanguage { didSet { defaults.set(responseLanguage.rawValue, forKey: Key.responseLanguage) } }
    /// Local history of requests and answers. Off by default.
    var keepHistory: Bool { didSet { defaults.set(keepHistory, forKey: Key.keepHistory) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.onlyOnMac: false,
            Key.closePanelAfterCopy: false,
            Key.keepHistory: false,
        ])
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        onlyOnMac = defaults.bool(forKey: Key.onlyOnMac)
        closePanelAfterCopy = defaults.bool(forKey: Key.closePanelAfterCopy)
        keepHistory = defaults.bool(forKey: Key.keepHistory)
        panelPosition = defaults.string(forKey: Key.panelPosition).flatMap(PanelPosition.init(rawValue:)) ?? .center
        responseLanguage = defaults.string(forKey: Key.responseLanguage).flatMap(ResponseLanguage.init(rawValue:)) ?? .automatic
    }

    /// Whether this build carries Private Cloud Compute. A seam for tests, which check that
    /// "Only on this Mac" keeps every request local even in a PCC build.
    @ObservationIgnored var privateCloudInBuild = BuildFeatures.isPrivateCloudCompiledIn

    var routingPolicy: RoutingPolicy { RoutingPolicy(onlyOnMac: onlyOnMac, privateCloudInBuild: privateCloudInBuild) }
}
