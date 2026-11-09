import Foundation
import NaturalLanguage
import Translation

/// Why a translation couldn't run. Language names are in the UI language.
enum TranslationFailure: LocalizedError, Equatable {
    case unknownLanguage
    case sameLanguage(String)
    case notDownloaded(String)
    case unsupported(String, String)
    case failed

    var errorDescription: String? {
        switch self {
        case .unknownLanguage:
            return String(localized: "Lampo couldn't tell which language the text is in. Select a little more text.")
        case .sameLanguage(let language):
            return String(localized: "The text is already in \(language). Choose another language.")
        case .notDownloaded(let languages):
            return String(localized: "Download \(languages) in System Settings › General › Language & Region › Translation Languages, then try again.")
        case .unsupported(let source, let target):
            return String(localized: "Translation from \(source) to \(target) isn't available on this Mac.")
        case .failed:
            return String(localized: "The translation didn't work. Try again.")
        }
    }
}

/// A source and target language, as BCP 47 identifiers ("it", "en", "zh-Hans").
struct TranslationPair: Equatable, Sendable {
    var source: String
    var target: String
}

/// Apple's Translation framework, abstracted for tests.
protocol Translating: Sendable {
    /// Translates `lines` (each one on its own, so the layout survives) on this Mac.
    func translate(_ lines: [String], pair: TranslationPair) async throws -> [String]
    /// Languages Translation offers, as identifiers, one per language.
    func supportedLanguages() async -> [String]
}

/// Picks the languages for a translation action. Pure, so it's tested without Translation.
enum TranslationPlanner {
    /// Value of `LampoAction.translationTarget` meaning "your language, or your other language".
    static let automatic = "auto"

    /// - Parameters:
    ///   - setting: the action's target, `automatic` or an identifier.
    ///   - override: a target chosen in the Lens, which wins over the setting.
    ///   - userLanguage: the language Lampo answers in ("it").
    ///   - otherLanguage: where text already in `userLanguage` goes ("en").
    static func pair(for text: String, setting: String, override: String?, userLanguage: String,
                     otherLanguage: String) throws -> TranslationPair {
        guard let source = detectLanguage(of: text) else { throw TranslationFailure.unknownLanguage }
        let target: String
        if let override {
            target = override
        } else if setting == automatic {
            target = sameLanguage(source, userLanguage) ? otherLanguage : userLanguage
        } else {
            target = setting
        }
        if sameLanguage(source, target) {
            throw TranslationFailure.sameLanguage(displayName(target))
        }
        return TranslationPair(source: source, target: target)
    }

    /// The text's dominant language, detected on device. Short texts get a looser threshold.
    static func detectLanguage(of text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(trimmed.prefix(2000)))
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              language != .undetermined else { return nil }
        let threshold = trimmed.count >= 20 ? 0.5 : 0.3
        return confidence >= threshold ? language.rawValue : nil
    }

    static func sameLanguage(_ a: String, _ b: String) -> Bool {
        let first = Locale.Language(identifier: a)
        let second = Locale.Language(identifier: b)
        return first.languageCode == second.languageCode
            && (first.script == nil || second.script == nil || first.script == second.script)
    }

    /// "inglese" in an Italian UI, "English" in an English one.
    static func displayName(_ identifier: String, locale: Locale = .current) -> String {
        locale.localizedString(forIdentifier: identifier)
            ?? locale.localizedString(forLanguageCode: identifier)
            ?? identifier
    }

    /// The language Lampo answers in, as an identifier. "Automatic" is the Mac's language,
    /// not the language of Lampo's menus.
    static func userLanguage(_ preference: ResponseLanguage, systemLanguage: String = SystemLanguage.code()) -> String {
        switch preference {
        case .italian: return "it"
        case .english: return "en"
        case .automatic: return systemLanguage
        }
    }

    /// The first of the Mac's preferred languages that isn't the user's own, else English (or Italian).
    static func defaultOtherLanguage(userLanguage: String,
                                     preferred: [String] = SystemLanguage.preferred()) -> String {
        for identifier in preferred {
            let language = Locale.Language(identifier: identifier)
            guard let code = language.languageCode?.identifier, !sameLanguage(code, userLanguage) else { continue }
            if code == "zh", let script = language.script?.identifier { return "zh-\(script)" }
            return code
        }
        return sameLanguage(userLanguage, "en") ? "it" : "en"
    }
}

/// Splits text into lines to translate and puts the translations back in place, so
/// paragraphs, blank lines, indentation and list markers stay where they were.
enum TranslationLayout {
    struct Line: Equatable {
        var indent: String
        var text: String
    }

    static func lines(of text: String) -> [Line] {
        text.components(separatedBy: "\n").map { line in
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            return Line(indent: indent, text: String(line.dropFirst(indent.count)))
        }
    }

    /// Lines with something to translate.
    static func translatable(_ lines: [Line]) -> [String] {
        lines.map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    static func join(_ lines: [Line], translations: [String]) -> String {
        var remaining = translations[...]
        return lines.map { line in
            guard !line.text.trimmingCharacters(in: .whitespaces).isEmpty,
                  let translated = remaining.popFirst() else { return line.indent + line.text }
            return line.indent + translated
        }.joined(separator: "\n")
    }
}

/// Translates with Apple's Translation framework, on this Mac. Languages must be downloaded:
/// an app without a window on screen can't show the download prompt, so Lampo explains where
/// to download them instead.
struct SystemTranslator: Translating {
    func translate(_ lines: [String], pair: TranslationPair) async throws -> [String] {
        guard !lines.isEmpty else { return [] }
        let source = Locale.Language(identifier: pair.source)
        let target = Locale.Language(identifier: pair.target)
        switch await LanguageAvailability().status(from: source, to: target) {
        case .installed:
            break
        case .supported:
            throw TranslationFailure.notDownloaded(
                [pair.source, pair.target].map { TranslationPlanner.displayName($0) }
                    .formatted(.list(type: .and)))
        case .unsupported:
            throw TranslationFailure.unsupported(TranslationPlanner.displayName(pair.source),
                                                 TranslationPlanner.displayName(pair.target))
        @unknown default:
            throw TranslationFailure.failed
        }
        let session = TranslationSession(installedSource: source, target: target)
        let requests = lines.enumerated().map { index, line in
            TranslationSession.Request(sourceText: line, clientIdentifier: String(index))
        }
        do {
            let responses = try await session.translations(from: requests)
            var byIndex: [Int: String] = [:]
            for response in responses {
                if let id = response.clientIdentifier.flatMap(Int.init) { byIndex[id] = response.targetText }
            }
            return lines.indices.map { byIndex[$0] ?? lines[$0] }
        } catch let error as TranslationFailure {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if TranslationError.notInstalled ~= error {
                throw TranslationFailure.notDownloaded(TranslationPlanner.displayName(pair.target))
            }
            if TranslationError.unableToIdentifyLanguage ~= error { throw TranslationFailure.unknownLanguage }
            Log.model.error("translation failed: \(error.localizedDescription, privacy: .public)")
            throw TranslationFailure.failed
        }
    }

    func supportedLanguages() async -> [String] {
        Self.uniqueLanguages(await LanguageAvailability().supportedLanguages.map { $0.maximalIdentifier })
    }

    /// One entry per language ("en", not "en-GB" too); Chinese keeps its two scripts.
    static func uniqueLanguages(_ identifiers: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for identifier in identifiers {
            let language = Locale.Language(identifier: identifier)
            guard let code = language.languageCode?.identifier else { continue }
            let key = code == "zh" ? "zh-\(language.script?.identifier ?? "Hans")" : code
            if seen.insert(key).inserted { result.append(key) }
        }
        return result
    }
}
