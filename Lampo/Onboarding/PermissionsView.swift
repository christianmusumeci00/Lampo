import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI

/// Live status of Lampo's permissions, with buttons that open the right System Settings pane.
struct PermissionsView: View {
    enum Style {
        case onboarding
        case settings
    }

    var style: Style = .settings
    var onDone: (() -> Void)?
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    @State private var calendarsGranted = false
    @State private var remindersGranted = false
    @State private var requestedScreenRecording = false
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    private let service = PermissionsService()
    private var calendars: CalendarService { Self.calendarService }
    /// One EventKit store for the app's lifetime (creating one is slow).
    private static let calendarService = CalendarService()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if style == .onboarding {
                HStack(spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(DesignTokens.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Let Lampo work where you are")
                            .font(.title3.weight(.semibold))
                        Text("Lampo reads the text you select and writes the result back in place. Nothing leaves your Mac.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            PermissionRow(
                title: "Accessibility",
                detail: "Read the selected text and replace it in any app.",
                isGranted: accessibilityGranted,
                grant: { service.grant(.accessibility) })

            PermissionRow(
                title: "Screen Recording",
                detail: "Look at the window you're using when you ask about the screen (⌘⇧S). Optional.",
                isGranted: screenRecordingGranted,
                grant: {
                    requestedScreenRecording = true
                    service.grant(.screenRecording)
                })

            if !screenRecordingGranted {
                if requestedScreenRecording {
                    ScreenRecordingHelp(
                        openSettings: { service.openScreenRecordingSettings() },
                        reveal: { service.revealApp() })
                } else {
                    Text("After allowing Screen Recording, macOS may ask you to quit and reopen Lampo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if style == .settings {
                // Asked the first time you dictate; shown here for status.
                PermissionRow(
                    title: "Microphone",
                    detail: "Listen while you dictate (⌥⇧D). Lampo hears nothing otherwise.",
                    isGranted: microphone == .authorized,
                    grant: grantMicrophone)

                // Asked the first time you confirm an event or a reminder; shown here for status.
                PermissionRow(
                    title: "Calendars",
                    detail: "Add the events you confirm. Lampo can't read your calendars.",
                    isGranted: calendarsGranted,
                    grant: { grantCalendar(.event) })

                PermissionRow(
                    title: "Reminders",
                    detail: "Add the reminders you confirm to your default list.",
                    isGranted: remindersGranted,
                    grant: { grantCalendar(.reminder) })
            }

            if style == .onboarding {
                HStack {
                    Text("You can change this later in Lampo Settings › Privacy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(accessibilityGranted ? "Done" : "Later") { onDone?() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .task {
            // Live status: System Settings doesn't notify apps when a permission changes.
            while !Task.isCancelled {
                accessibilityGranted = AXIsProcessTrusted()
                screenRecordingGranted = CGPreflightScreenCaptureAccess()
                if style == .settings {
                    microphone = AVCaptureDevice.authorizationStatus(for: .audio)
                    calendarsGranted = calendars.access(for: .event) == .granted
                    remindersGranted = calendars.access(for: .reminder) == .granted
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

extension PermissionsView {
    /// First time: the system prompt. After a refusal: the System Settings pane.
    private func grantMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            Task { _ = await AVCaptureDevice.requestAccess(for: .audio) }
        } else {
            SystemDictationEngine.openMicrophoneSettings()
        }
    }

    /// First time: the system prompt. After a refusal: the System Settings pane.
    private func grantCalendar(_ kind: DraftKind) {
        if calendars.access(for: kind) == .notDetermined {
            Task { _ = await calendars.requestAccess(for: kind) }
        } else {
            calendars.openSettings(for: kind)
        }
    }
}

/// What to do after "Allow…" for Screen Recording: macOS 27 doesn't let apps add themselves.
private struct ScreenRecordingHelp: View {
    let openSettings: () -> Void
    let reveal: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In the macOS alert, click “Open System Settings” and turn on Lampo. If Lampo isn't in the list, click + and choose Lampo (or drag it in from the Finder). Then quit and reopen Lampo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Open System Settings", action: openSettings)
                Button("Show Lampo in Finder", action: reveal)
            }
            .controlSize(.small)
        }
        .padding(.leading, 30)
    }
}

struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let isGranted: Bool
    let grant: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 18))
                .foregroundStyle(isGranted ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isGranted {
                Text("Allowed").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Button("Allow…", action: grant)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isGranted ? "Allowed" : "Not allowed"))
    }
}

/// Small window that hosts `PermissionsView` when an action needs a permission (first launch uses `WelcomeView`).
@MainActor
final class OnboardingWindowController {
    private var window: FrontWindow?
    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionsView(style: .onboarding) { [weak self] in
                self?.window?.close()
            }
            .padding(24)
            .frame(width: 480))
            let window = FrontWindow(contentViewController: hosting)
            window.title = String(localized: "Lampo Permissions")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.presentAboveEverything()
    }
}
