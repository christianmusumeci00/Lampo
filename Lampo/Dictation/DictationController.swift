import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Esc while Lampo listens: registered only during dictation, so Esc otherwise reaches the apps.
    static let cancelDictation = Self("cancelDictation", initial: .init(.escape))
}

/// "Dictate": hold the shortcut and talk (released after a moment: stop), or press it once and
/// press it again to stop. Esc cancels. The transcript is cleaned up by the model with the action's
/// prompt and typed where the cursor is, as one paste (⌘Z undoes it).
@MainActor
final class DictationController {
    enum Phase: Equatable {
        case idle
        case starting
        case listening
        case finishing
    }

    /// A press shorter than this keeps listening until the next press (toggle); a longer one is
    /// push-to-talk and stops on release.
    static let holdThreshold: Duration = .milliseconds(400)
    /// Listening stops by itself after this long.
    static let maximumDuration: Duration = .seconds(300)

    private(set) var phase: Phase = .idle
    let hud: DictationHUDModel

    private let engine: any DictationEngine
    private let runner: ActionRunner
    private let output: OutputService
    private let permissions: any PermissionsChecking
    private let hotkeys: any HotkeyBackend
    private let statusHUD: HUDController
    private let language: () -> String
    private let clock: () -> ContinuousClock.Instant

    private var action: LampoAction?
    private var target: SourceApp?
    private var pressedAt: ContinuousClock.Instant?
    private var stopRequested = false
    private var cancelRequested = false
    private var updatesTask: Task<Void, Never>?
    private var limitTask: Task<Void, Never>?
    private(set) var work: Task<Void, Never>?

    /// Shows or hides the listening capsule (the panel lives in `DictationHUDController`).
    var onShowHUD: ((Bool) -> Void)?
    /// The speech model isn't on this Mac: open Settings, where it can be downloaded.
    var onNeedsModel: (() -> Void)?
    /// "Open in the panel" actions: the panel runs the prompt with the transcript.
    var onOpenPanel: ((LampoAction, TemplateContext) -> Void)?
    /// "Create event/reminder" actions: the transcript becomes a draft card.
    var onShowDraft: ((DraftKind, String) -> Void)?
    /// "Extract" actions: the transcript goes to the Extract card.
    var onExtract: ((String) -> Void)?
    /// Finished dictations, for the history: action name, transcript, inserted text, route.
    var onResult: ((String, String, String, ModelRoute) -> Void)?

    init(engine: any DictationEngine, runner: ActionRunner, output: OutputService,
         permissions: any PermissionsChecking, hotkeys: any HotkeyBackend, statusHUD: HUDController,
         hud: DictationHUDModel = DictationHUDModel(), language: @escaping () -> String,
         clock: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }) {
        self.engine = engine
        self.runner = runner
        self.output = output
        self.permissions = permissions
        self.hotkeys = hotkeys
        self.statusHUD = statusHUD
        self.hud = hud
        self.language = language
        self.clock = clock
    }

    var isActive: Bool { phase != .idle }

    // MARK: Keys

    func keyDown(_ action: LampoAction) {
        switch phase {
        case .idle:
            begin(action)
        case .starting, .listening:
            finish()
        case .finishing:
            break
        }
    }

    /// Only the release of the press that started listening counts.
    func keyUp(_ actionID: UUID) {
        guard phase == .starting || phase == .listening, actionID == action?.id, let pressedAt else { return }
        self.pressedAt = nil
        if clock() - pressedAt >= Self.holdThreshold {
            finish()
        }
    }

    // MARK: Flow

    private func begin(_ action: LampoAction) {
        phase = .starting
        self.action = action
        target = SourceApp.frontmost()
        pressedAt = clock()
        stopRequested = false
        cancelRequested = false
        hud.reset(shortcut: KeyboardShortcuts.getShortcut(for: action.shortcutName)?.description)
        work = Task { await start(action) }
    }

    private func start(_ action: LampoAction) async {
        switch engine.microphoneAccess {
        case .granted:
            break
        case .denied:
            fail(DictationError.microphoneDenied)
            SystemDictationEngine.openMicrophoneSettings()
            return
        case .notDetermined:
            guard await engine.requestMicrophone() else {
                fail(DictationError.microphoneDenied)
                return
            }
            // The system prompt took the key's release: keep listening until the next press.
            pressedAt = nil
        }

        let language = language()
        switch await engine.readiness(for: language) {
        case .ready:
            break
        case .needsDownload:
            fail(DictationError.modelNotDownloaded(TranslationPlanner.displayName(language)))
            onNeedsModel?()
            return
        case .unsupported:
            fail(DictationError.unsupportedLanguage(TranslationPlanner.displayName(language)))
            return
        }

        let updates: AsyncStream<DictationUpdate>
        do {
            updates = try await engine.start(language: language)
        } catch {
            fail(error)
            return
        }
        if cancelRequested {
            await engine.cancel()
            reset()
            return
        }
        phase = .listening
        hud.phase = .listening
        onShowHUD?(true)
        hotkeys.onKeyDown(for: .cancelDictation) { [weak self] in self?.cancel() }
        updatesTask = Task { [hud] in
            for await update in updates {
                switch update {
                case .text(let text): hud.transcript = text
                case .level(let level): hud.level = level
                }
            }
        }
        limitTask = Task { [weak self] in
            try? await Task.sleep(for: Self.maximumDuration)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
        if stopRequested { finish() }
    }

    /// Stops listening, cleans the transcript up and delivers it.
    func finish() {
        switch phase {
        case .starting:
            stopRequested = true
            return
        case .listening:
            break
        case .idle, .finishing:
            return
        }
        guard let action else { return }
        phase = .finishing
        stopListeningUI()
        hud.phase = .finishing
        work = Task { await complete(action) }
    }

    /// Esc: stops listening and drops what was said.
    func cancel() {
        switch phase {
        case .starting:
            cancelRequested = true
        case .listening:
            phase = .finishing
            stopListeningUI()
            onShowHUD?(false)
            work = Task {
                await engine.cancel()
                reset()
            }
        case .idle, .finishing:
            break
        }
    }

    private func complete(_ action: LampoAction) async {
        let transcript: String
        do {
            transcript = try await engine.stop()
        } catch {
            fail(error)
            return
        }
        updatesTask?.cancel()
        guard !transcript.isEmpty else {
            fail(DictationError.nothingHeard)
            return
        }

        var context = runner.templateContext(selection: nil, clipboard: nil, app: target?.name)
        context.dictation = transcript
        switch action.effectiveOutput {
        case .openPanel:
            reset()
            onOpenPanel?(action, context)
            return
        case .calendarEvent, .reminder:
            reset()
            onShowDraft?(action.output.draftKind ?? .event, transcript)
            return
        case .extract:
            reset()
            onExtract?(transcript)
            return
        case .preview, .replaceSilently, .copy:
            break
        }

        let (text, route, note) = await cleanUp(transcript, with: action, context: context)
        onResult?(action.name, transcript, text, route)
        reset()
        let anchor: CGRect? = nil
        if action.effectiveOutput == .copy || !permissions.isAccessibilityGranted {
            output.copy(text)
            statusHUD.show(note ?? String(localized: "Copied: paste it with ⌘V"), style: .success, near: anchor)
        } else {
            await output.insert(text, into: target)
            statusHUD.show(note ?? String(localized: "Done · ⌘Z to undo"), style: .success, near: anchor)
        }
    }

    /// The model's cleanup, or the transcript as said when there's no prompt, the model can't run,
    /// or the transcript was too long (a cleaned excerpt would lose words).
    private func cleanUp(_ transcript: String, with action: LampoAction,
                         context: TemplateContext) async -> (String, ModelRoute, String?) {
        guard !action.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (transcript, .onDevice, nil)
        }
        do {
            let run = try await runner.start(action, context: context)
            var last = ""
            for try await text in run.stream { last = text }
            if run.wasTruncated {
                return (transcript, run.route, String(localized: "Long dictation: inserted as you said it"))
            }
            let cleaned = RewriteCleaner.clean(last, original: transcript)
            return cleaned.isEmpty ? (transcript, run.route, nil) : (cleaned, run.route, nil)
        } catch {
            Log.model.info("dictation cleanup skipped: \(String(describing: type(of: error)), privacy: .public)")
            return (transcript, .onDevice, String(localized: "Inserted as you said it: the model isn't available"))
        }
    }

    private func stopListeningUI() {
        hotkeys.removeHandler(for: .cancelDictation)
        limitTask?.cancel()
        limitTask = nil
    }

    private func fail(_ error: any Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? DictationError.failed.localizedDescription
        stopListeningUI()
        updatesTask?.cancel()
        reset()
        statusHUD.show(message, style: .failure, near: nil)
    }

    private func reset() {
        updatesTask?.cancel()
        updatesTask = nil
        phase = .idle
        hud.phase = .idle
        onShowHUD?(false)
        pressedAt = nil
        action = nil
    }
}
