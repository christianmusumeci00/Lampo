import AppKit
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
    private let service = PermissionsService()

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
                grant: { service.grant(.screenRecording) })

            if !screenRecordingGranted {
                Text("After allowing Screen Recording, macOS may ask you to quit and reopen Lampo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                try? await Task.sleep(for: .seconds(1))
            }
        }
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

/// Small window that hosts `PermissionsView` for first launch and blocked actions.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private static let shownKey = "didShowPermissionsOnboarding"

    func showIfFirstLaunch(accessibilityGranted: Bool, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Self.shownKey), !accessibilityGranted else { return }
        defaults.set(true, forKey: Self.shownKey)
        show()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: PermissionsView(style: .onboarding) { [weak self] in
                self?.window?.close()
            }
            .padding(24)
            .frame(width: 480))
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Lampo Permissions")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
