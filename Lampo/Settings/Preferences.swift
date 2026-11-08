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
        static let rewriteTone = "rewriteTone"
        static let translationLanguage = "translationLanguage"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.isEnabled) } }
    var onlyOnMac: Bool { didSet { defaults.set(onlyOnMac, forKey: Key.onlyOnMac) } }
    var closePanelAfterCopy: Bool { didSet { defaults.set(closePanelAfterCopy, forKey: Key.closePanelAfterCopy) } }
    var panelPosition: PanelPosition { didSet { defaults.set(panelPosition.rawValue, forKey: Key.panelPosition) } }
    var responseLanguage: ResponseLanguage { didSet { defaults.set(responseLanguage.rawValue, forKey: Key.responseLanguage) } }
    /// Local history of requests and answers. Off by default.
    var keepHistory: Bool { didSet { defaults.set(keepHistory, forKey: Key.keepHistory) } }
    /// Last tone picked for "Rewrite".
    var rewriteTone: RewriteTone { didSet { defaults.set(rewriteTone.rawValue, forKey: Key.rewriteTone) } }
    /// Where "Translate" sends text that is already in your language; nil until you pick one.
    var translationLanguage: String? { didSet { defaults.set(translationLanguage, forKey: Key.translationLanguage) } }

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
        rewriteTone = defaults.string(forKey: Key.rewriteTone).flatMap(RewriteTone.init(rawValue:)) ?? .clearer
        translationLanguage = defaults.string(forKey: Key.translationLanguage)
    }

    /// The language Lampo answers in, as an identifier ("it").
    var userLanguage: String { TranslationPlanner.userLanguage(responseLanguage) }

    /// Where "Translate" sends text that is already in `userLanguage`.
    var otherLanguage: String {
        if let translationLanguage, !TranslationPlanner.sameLanguage(translationLanguage, userLanguage) {
            return translationLanguage
        }
        return TranslationPlanner.defaultOtherLanguage(userLanguage: userLanguage)
    }

    /// Whether this build carries Private Cloud Compute. A seam for tests, which check that
    /// "Only on this Mac" keeps every request local even in a PCC build.
    @ObservationIgnored var privateCloudInBuild = BuildFeatures.isPrivateCloudCompiledIn

    var routingPolicy: RoutingPolicy { RoutingPolicy(onlyOnMac: onlyOnMac, privateCloudInBuild: privateCloudInBuild) }
}
