import AppKit
import Foundation

/// The language of Lampo's own windows and menus, English unless the user picks Italian.
///
/// It's stored as `AppleLanguages` in Lampo's own defaults domain, which is what `Bundle.main`
/// reads to pick a localization, so a change takes effect when Lampo relaunches. The Mac's own
/// languages (the global domain) keep deciding the answer, translation and dictation defaults:
/// see `SystemLanguage`.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case italian = "it"

    static let defaultsKey = "AppleLanguages"

    var id: String { rawValue }

    /// Each language in its own name, as language pickers show them.
    var nativeName: String {
        switch self {
        case .english: return "English"
        case .italian: return "Italiano"
        }
    }

    /// The language saved in `domain`, or English when none is saved.
    static func current(defaults: UserDefaults = .standard, domain: String = AppLanguage.appDomain) -> AppLanguage {
        guard let saved = savedLanguages(defaults: defaults, domain: domain)?.first else { return .english }
        return allCases.first { $0.rawValue == Locale.Language(identifier: saved).languageCode?.identifier } ?? .english
    }

    /// Saves English on the first launch, so Lampo starts in English even on an Italian Mac.
    /// Returns true when it wrote something.
    @discardableResult
    static func applyDefault(defaults: UserDefaults = .standard, domain: String = AppLanguage.appDomain) -> Bool {
        guard savedLanguages(defaults: defaults, domain: domain) == nil else { return false }
        defaults.set([AppLanguage.english.rawValue], forKey: defaultsKey)
        return true
    }

    /// Saves the choice. Lampo has to relaunch to show it (`AppRelauncher`).
    static func choose(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        defaults.set([language.rawValue], forKey: defaultsKey)
    }

    /// Only Lampo's own domain: `defaults.array(forKey:)` would fall back to the Mac's languages.
    private static func savedLanguages(defaults: UserDefaults, domain: String) -> [String]? {
        defaults.persistentDomain(forName: domain)?[defaultsKey] as? [String]
    }

    static var appDomain: String { Bundle.main.bundleIdentifier ?? "app.lampo.Lampo" }
}

/// The Mac's own languages (System Settings › General › Language & Region), not Lampo's.
///
/// `Locale.current` and `Locale.preferredLanguages` follow Lampo's `AppleLanguages`, so once
/// Lampo runs in English they'd say English on an Italian Mac. Answers ("Same as the
/// question"), Translate and Dictate must keep following the Mac.
enum SystemLanguage {
    static func preferred(global: [String: Any]? = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)) -> [String] {
        let languages = global?[AppLanguage.defaultsKey] as? [String] ?? []
        return languages.isEmpty ? Locale.preferredLanguages : languages
    }

    /// The language code of the Mac's first language, e.g. "it".
    static func code(preferred: [String] = SystemLanguage.preferred()) -> String {
        preferred.first.flatMap { Locale.Language(identifier: $0).languageCode?.identifier } ?? "en"
    }
}

/// Quits Lampo and opens it again once it has quit (used after changing its language).
@MainActor
enum AppRelauncher {
    static func relaunch() {
        // Waits for this process to exit, then opens this same copy of Lampo.
        let script = "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\""
        guard spawnDetached(["/bin/sh", "-c", script, Bundle.main.bundlePath]) else { return }
        NSApp.terminate(nil)
    }

    /// Starts `arguments` in a session of its own. When Lampo was opened from the Finder or
    /// the Dock, launchd ends the processes in its process group as it quits, which killed a
    /// helper started with `Process` before it could reopen Lampo.
    private static func spawnDetached(_ arguments: [String]) -> Bool {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let status = posix_spawn(&pid, arguments[0], nil, &attributes, &argv, environ)
        if status != 0 {
            Log.app.error("couldn't relaunch: posix_spawn \(status, privacy: .public)")
        }
        return status == 0
    }
}
