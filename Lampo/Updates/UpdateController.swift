import AppKit
import Observation
import Sparkle

/// Release settings read from Info.plist. Empty in development builds.
struct ReleaseInfo: Equatable {
    var feedURL: URL?
    var publicKey: String
    var website: URL?
    var repository: URL?

    init(info: [String: Any]) {
        func url(_ key: String) -> URL? {
            guard let value = (info[key] as? String)?.trimmingCharacters(in: .whitespaces),
                  let url = URL(string: value), url.scheme == "https" else { return nil }
            return url
        }
        feedURL = url("SUFeedURL")
        publicKey = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        website = url("LampoWebsiteURL")
        repository = url("LampoRepositoryURL")
    }

    static var main: ReleaseInfo { ReleaseInfo(info: Bundle.main.infoDictionary ?? [:]) }

    /// Sparkle runs only with an HTTPS feed and an EdDSA public key (updates are signature-checked).
    var updatesConfigured: Bool { feedURL != nil && !publicKey.isEmpty }
}

/// Sparkle, the only network use besides Private Cloud Compute. It checks the appcast only after
/// the user agrees (Sparkle asks on the second launch) or presses "Check for Updates…";
/// no system profile is sent.
@MainActor
@Observable
final class UpdateController: NSObject, SPUStandardUserDriverDelegate {
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    /// A scheduled check found an update the user hasn't looked at yet (shown in the menu).
    private(set) var hasPendingUpdate = false
    private(set) var automaticallyChecks = false

    let release: ReleaseInfo

    init(release: ReleaseInfo = .main) {
        self.release = release
        super.init()
    }

    var isAvailable: Bool { controller != nil }

    func start() {
        guard controller == nil, release.updatesConfigured else {
            Log.app.info("updates not configured in this build")
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        hasPendingUpdate = false
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ value: Bool) {
        controller?.updater.automaticallyChecksForUpdates = value
        automaticallyChecks = controller?.updater.automaticallyChecksForUpdates ?? false
    }

    // MARK: SPUStandardUserDriverDelegate (gentle reminders for a menu bar app)

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        let scheduled = !state.userInitiated
        MainActor.assumeIsolated {
            if scheduled { hasPendingUpdate = true }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { hasPendingUpdate = false }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { hasPendingUpdate = false }
    }
}
