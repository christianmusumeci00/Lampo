import AppKit
import AVFoundation
import CoreGraphics
import KeyboardShortcuts
import Observation
import SwiftUI

/// The steps of the welcome guide, in order.
enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case features
    case accessibility
    case screenRecording
    case dictation
    case calendars
    case preferences
    case ready

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
}

/// Where the guide is, saved so it opens again at the same step after Lampo relaunches (macOS
/// asks to quit and reopen after Screen Recording; changing the language relaunches too).
struct OnboardingProgress {
    static let finishedKey = "didShowWelcome"
    static let stepKey = "onboardingStep"

    let defaults: UserDefaults

    var isFinished: Bool { defaults.bool(forKey: Self.finishedKey) }

    var step: OnboardingStep {
        get { OnboardingStep(rawValue: defaults.integer(forKey: Self.stepKey)) ?? .welcome }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.stepKey) }
    }

    /// Done (or closed): the guide doesn't open by itself again, and opens from the start from the menu.
    func finish() {
        defaults.set(true, forKey: Self.finishedKey)
        defaults.removeObject(forKey: Self.stepKey)
    }
}

/// Live status of the permissions the guide asks for. System Settings doesn't tell apps when a
/// permission changes, so it's polled while the guide is open.
@MainActor
@Observable
final class PermissionMonitor {
    /// Reads each permission's current status (the system's, or a test's).
    struct Probe {
        var accessibility: () -> Bool
        var screenRecording: () -> Bool
        var microphone: () -> AVAuthorizationStatus
        var calendars: () -> Bool
        var reminders: () -> Bool

        @MainActor static var system: Probe {
            Probe(
            accessibility: { AXIsProcessTrusted() },
            screenRecording: { CGPreflightScreenCaptureAccess() },
            microphone: { AVCaptureDevice.authorizationStatus(for: .audio) },
            calendars: { PermissionsView.calendarService.access(for: .event) == .granted },
            reminders: { PermissionsView.calendarService.access(for: .reminder) == .granted })
        }
    }

    private(set) var accessibility: Bool
    private(set) var screenRecording: Bool
    private(set) var microphone: AVAuthorizationStatus = .notDetermined
    private(set) var calendars = false
    private(set) var reminders = false
    /// Accessibility or Screen Recording was just turned on (in System Settings).
    @ObservationIgnored var onGranted: (() -> Void)?
    @ObservationIgnored private let probe: Probe

    init(probe: Probe = .system) {
        self.probe = probe
        accessibility = probe.accessibility()
        screenRecording = probe.screenRecording()
    }

    func refresh() {
        let accessibility = probe.accessibility()
        let screenRecording = probe.screenRecording()
        let newlyGranted = (accessibility && !self.accessibility) || (screenRecording && !self.screenRecording)
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        microphone = probe.microphone()
        calendars = probe.calendars()
        reminders = probe.reminders()
        if newlyGranted { onGranted?() }
    }

    func watch() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

/// The guide's state: the current step, saved as it changes.
@MainActor
@Observable
final class OnboardingModel {
    var step: OnboardingStep {
        didSet { progress.step = step }
    }
    let permissions: PermissionMonitor
    /// Screen Recording's "Allow…" was clicked: show what to do in System Settings.
    var requestedScreenRecording = false
    @ObservationIgnored private let progress: OnboardingProgress
    /// Closes the guide; true also opens the panel ("Try it now").
    @ObservationIgnored var onFinish: (_ openPanel: Bool) -> Void = { _ in }

    init(progress: OnboardingProgress, permissions: PermissionMonitor = PermissionMonitor()) {
        self.progress = progress
        self.permissions = permissions
        self.step = progress.isFinished ? .welcome : progress.step
    }

    func goForward() {
        if let next = step.next { step = next } else { onFinish(false) }
    }

    func goBack() {
        if let previous = step.previous { step = previous }
    }
}

/// First launch: what Lampo does, then each permission and setting, one step at a time.
struct WelcomeView: View {
    @Bindable var model: OnboardingModel
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                stepContent
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 36)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            Divider()
            footer
        }
        .task { await model.permissions.watch() }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch model.step {
        case .welcome: WelcomeStep(state: state)
        case .features: FeaturesStep()
        case .accessibility: AccessibilityStep(model: model)
        case .screenRecording: ScreenRecordingStep(model: model)
        case .dictation: DictationStep(model: model, state: state)
        case .calendars: CalendarsStep(model: model)
        case .preferences: PreferencesStep(state: state)
        case .ready: ReadyStep { model.onFinish(true) }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            StepDots(current: model.step)
            Spacer()
            if model.step.previous != nil {
                Button("Back") { model.goBack() }
                    .keyboardShortcut(.cancelAction)
            }
            Button(model.step.next == nil ? "Done" : "Continue") { model.goForward() }
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

private struct StepDots: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Circle()
                    .fill(step == current ? AnyShapeStyle(DesignTokens.accent) : AnyShapeStyle(.quaternary))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Step \(current.rawValue + 1) of \(OnboardingStep.allCases.count)"))
    }
}

/// Symbol, title and one paragraph at the top of a step.
private struct StepHeader: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(DesignTokens.accent)
                .frame(width: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 6)
    }
}

/// Numbered instructions, e.g. what to do in System Settings.
private struct NumberedSteps: View {
    let steps: [LocalizedStringKey]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(steps.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: "\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(DesignTokens.accent))
                        .accessibilityHidden(true)
                    Text(steps[index])
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
    }
}

private struct Note: View {
    let text: LocalizedStringKey
    var symbol = "info.circle"

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

// MARK: Steps

private struct WelcomeStep: View {
    @Bindable var state: AppState
    @State private var language = AppLanguage.current()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome to Lampo")
                        .font(.largeTitle.weight(.semibold))
                    Text("Your Mac's intelligence, one shortcut away. On your text, your screen, your apps.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Note(text: "Offline, free and private. Nothing leaves your Mac unless you ask for Private Cloud Compute, and Lampo always tells you where a request ran.",
                 symbol: "lock.fill")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Language")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Picker("Language", selection: $language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(verbatim: language.nativeName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: language) { _, newValue in
                        AppLanguage.choose(newValue)
                        AppRelauncher.relaunch()
                    }
                }
                Text("Lampo restarts in the language you choose. You can change it later in Settings › General.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))

            availability

            Note(text: "Next: a quick tour, then the permissions Lampo needs, one at a time. It takes about two minutes.",
                 symbol: "list.number")
        }
    }

    @ViewBuilder
    private var availability: some View {
        switch state.availability {
        case .available:
            Label("Apple Intelligence is ready on this Mac.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .unknown:
            EmptyView()
        default:
            AvailabilityView(availability: state.availability, style: .compact) { state.refreshAvailability() }
        }
    }
}

private struct FeaturesStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeader(symbol: "sparkles", title: "What Lampo does",
                       detail: "Everything works in any app, with a shortcut. These are the ones to remember.")
            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(shortcuts: [.togglePanel], symbol: "bolt.fill",
                           title: "Ask from anywhere",
                           detail: "Open the panel over any app. It sees the text you selected, and the answer starts right away.")
                FeatureRow(shortcuts: names([BuiltInActions.correctID, BuiltInActions.rewriteID, BuiltInActions.translateID]),
                           symbol: "text.cursor",
                           title: "Correct, rewrite, translate",
                           detail: "Select text and press a shortcut: Lampo previews the result and replaces it in place. ⌘Z undoes it.")
                FeatureRow(shortcuts: names([BuiltInActions.replyID]), symbol: "arrowshape.turn.up.left",
                           title: "Reply",
                           detail: "Select a message: Lampo drafts the reply in its language and types it where your cursor is.")
                FeatureRow(shortcuts: names([BuiltInActions.dictateID]), symbol: "mic",
                           title: "Dictate",
                           detail: "Hold the shortcut and talk. Lampo tidies up what you said and types it.")
                FeatureRow(shortcuts: names([BuiltInActions.askScreenID]), symbol: "macwindow",
                           title: "Ask about the screen",
                           detail: "Lampo looks at the window you're using and reads its text: an error, a chart, a form.")
                FeatureRow(shortcuts: names([BuiltInActions.createEventID, BuiltInActions.createReminderID, BuiltInActions.extractID]),
                           symbol: "calendar.badge.plus",
                           title: "Events, reminders and more",
                           detail: "Turn selected text into events, reminders, a contact or a table. Nothing is saved until you confirm.")
            }
            Note(text: "You can change every shortcut, and turn actions off, in Settings.")
        }
    }

    private func names(_ ids: [UUID]) -> [KeyboardShortcuts.Name] {
        ids.compactMap(BuiltInActions.shortcutName(for:))
    }
}

private struct FeatureRow: View {
    let shortcuts: [KeyboardShortcuts.Name]
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DesignTokens.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    ForEach(keys, id: \.self) { ShortcutChip(keys: $0) }
                }
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var keys: [String] {
        shortcuts.compactMap { KeyboardShortcuts.getShortcut(for: $0)?.description }
    }
}

private struct ShortcutChip: View {
    let keys: String
    var large = false

    var body: some View {
        Text(verbatim: keys)
            .font(.system(size: large ? 22 : 12, weight: .medium, design: .rounded))
            .padding(.horizontal, large ? 14 : 7)
            .padding(.vertical, large ? 6 : 2)
            .background(RoundedRectangle(cornerRadius: large ? 9 : 5).fill(.quaternary))
            .accessibilityLabel(Text("Shortcut \(keys)"))
    }
}

private struct AccessibilityStep: View {
    @Bindable var model: OnboardingModel
    private let service = PermissionsService()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "accessibility", title: "Allow Accessibility",
                       detail: "Lampo needs it to read the text you select and to write the result back in place, in any app. It's the one permission Lampo really needs.")
            PermissionRow(title: "Accessibility",
                          detail: "Read the selected text and replace it in any app.",
                          isGranted: model.permissions.accessibility,
                          grant: { service.grant(.accessibility) })
            if model.permissions.accessibility {
                Label("Done: Lampo can work with the text you select.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                NumberedSteps(steps: [
                    "Click “Allow…”. macOS opens System Settings › Privacy & Security › Accessibility.",
                    "Turn on Lampo. macOS may ask for your password or Touch ID.",
                    "Come back here: this window returns by itself when it's done. If you lose it, click Lampo in the Dock.",
                ])
            }
        }
    }
}

private struct ScreenRecordingStep: View {
    @Bindable var model: OnboardingModel
    private let service = PermissionsService()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "macwindow", title: "Allow Screen Recording",
                       detail: "Optional, only for “Ask the screen”: Lampo looks at the window you're using, only when you ask, and never keeps the picture.")
            PermissionRow(title: "Screen Recording",
                          detail: "Look at the window you're using when you ask about the screen.",
                          isGranted: model.permissions.screenRecording,
                          grant: {
                              model.requestedScreenRecording = true
                              service.grant(.screenRecording)
                          })
            if model.permissions.screenRecording {
                Label("Done: Lampo can look at the window you're using.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                if model.requestedScreenRecording {
                    ScreenRecordingHelp(openSettings: { service.openScreenRecordingSettings() },
                                        reveal: { service.revealApp() })
                }
                Note(text: "If macOS asks you to quit and reopen Lampo, do it: this guide opens again at this step. If you lose this window, click Lampo in the Dock.")
            }
        }
    }
}

private struct DictationStep: View {
    @Bindable var model: OnboardingModel
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "mic", title: "Dictation",
                       detail: "Hold the Dictate shortcut and talk, or press it once to start and again to stop. Your voice becomes text on this Mac.")
            PermissionRow(title: "Microphone",
                          detail: "Listen while you dictate. Lampo hears nothing otherwise.",
                          isGranted: model.permissions.microphone == .authorized,
                          grant: PermissionsView.grantMicrophone)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Speech model (\(TranslationPlanner.displayName(state.preferences.dictationLanguageIdentifier)))")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Downloaded once from Apple. What you say never leaves your Mac.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                SpeechModelStatus(state: state)
            }
            Note(text: "Optional: you can also do this the first time you dictate.")
        }
    }
}

private struct CalendarsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "calendar.badge.plus", title: "Events and reminders",
                       detail: "Select text with a date, like “dinner with Anna Friday at 8”, and Lampo prepares the event. It always shows you a card first: nothing is saved until you confirm.")
            PermissionRow(title: "Calendars",
                          detail: "Add the events you confirm. Lampo can't read your calendars.",
                          isGranted: model.permissions.calendars,
                          grant: { PermissionsView.grantCalendar(.event) })
            PermissionRow(title: "Reminders",
                          detail: "Add the reminders you confirm to your default list.",
                          isGranted: model.permissions.reminders,
                          grant: { PermissionsView.grantCalendar(.reminder) })
            Note(text: "Optional: macOS also asks the first time you confirm an event or a reminder.")
        }
    }
}

private struct PreferencesStep: View {
    @Bindable var state: AppState

    var body: some View {
        @Bindable var preferences = state.preferences
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "gearshape", title: "A few preferences",
                       detail: "Good defaults are already set. Everything else is in Lampo Settings.")
            Form {
                LaunchAtLoginToggle()
                Picker("Panel position", selection: $preferences.panelPosition) {
                    Text("Center of the screen").tag(PanelPosition.center)
                    Text("Near the pointer").tag(PanelPosition.nearCursor)
                }
                Picker("Answer language", selection: $preferences.responseLanguage) {
                    Text("Same as the question").tag(ResponseLanguage.automatic)
                    Text("Italian").tag(ResponseLanguage.italian)
                    Text("English").tag(ResponseLanguage.english)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, -20)
        }
    }
}

private struct ReadyStep: View {
    let tryIt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHeader(symbol: "checkmark.seal.fill", title: "You're ready",
                       detail: "Lampo lives in the menu bar, under the lightning bolt. From there you can open Settings and this guide again.")
            HStack(spacing: 16) {
                if let keys = KeyboardShortcuts.getShortcut(for: .togglePanel)?.description {
                    ShortcutChip(keys: keys, large: true)
                }
                Text("Press it in any app and ask something. Try it on a selected paragraph: “summarize this”.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Try it now", action: tryIt)
                .controlSize(.large)
        }
    }
}

// MARK: Window

/// The welcome guide's window: opens by itself until the guide is finished, centered, with a
/// Dock icon while it's open (`DockPresence`). It comes back in front by itself when a permission
/// is turned on in System Settings.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 640, height: 560)

    private var window: FrontWindow?
    private let progress: OnboardingProgress

    init(defaults: UserDefaults = .standard) {
        progress = OnboardingProgress(defaults: defaults)
    }

    var isShowing: Bool { window != nil }

    func showIfFirstLaunch(state: AppState) {
        guard !progress.isFinished else { return }
        show(state: state)
    }

    func show(state: AppState) {
        if window == nil {
            let model = OnboardingModel(progress: progress)
            model.onFinish = { [weak self, weak state] openPanel in
                self?.finish()
                if openPanel { state?.togglePanel() }
            }
            model.permissions.onGranted = { [weak self] in self?.window?.presentAboveEverything() }
            let window = FrontWindow.make(title: String(localized: "Welcome to Lampo"), size: Self.size,
                                          content: WelcomeView(model: model, state: state))
            window.delegate = self
            self.window = window
        }
        guard let window else { return }
        DockPresence.shared.attach(window)
        window.presentAboveEverything()
    }

    private func finish() {
        progress.finish()
        window?.close()
    }

    /// The close button (or ⌘W) ends the guide. Quitting Lampo doesn't close windows, so the
    /// guide reopens at the same step after a relaunch.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        progress.finish()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
