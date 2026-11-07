import Foundation
import Testing
@testable import Lampo

@MainActor
struct PreferencesTests {
    @Test func defaultsAndPersistence() {
        let defaults = makeTestDefaults()
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.isEnabled)
        #expect(!preferences.onlyOnMac)
        #expect(preferences.panelPosition == .center)

        preferences.isEnabled = false
        preferences.onlyOnMac = true
        preferences.panelPosition = .nearCursor
        preferences.responseLanguage = .italian

        let reloaded = Preferences(defaults: defaults)
        #expect(!reloaded.isEnabled)
        #expect(reloaded.onlyOnMac)
        #expect(reloaded.panelPosition == .nearCursor)
        #expect(reloaded.responseLanguage == .italian)
        #expect(!reloaded.routingPolicy.allowsPrivateCloud)
    }
}
