import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

/// The privacy permissions Lampo asks for.
enum PermissionKind: Equatable, Sendable {
    case accessibility
    case screenRecording
}

/// Status and requests for the privacy permissions Lampo needs.
@MainActor
protocol PermissionsChecking: AnyObject {
    var isAccessibilityGranted: Bool { get }
    var isScreenRecordingGranted: Bool { get }
    func requestAccessibility()
    func openAccessibilitySettings()
    /// Registers Lampo for Screen Recording (adds it to the list in System Settings, shows the prompt).
    func requestScreenRecording() async
    func openScreenRecordingSettings()
    /// True while macOS shows its own "… would like to …" alert (it has "Open System Settings").
    var isSystemPrivacyAlertShowing: Bool { get }
    /// Shows Lampo.app in the Finder, to drag it into the list or pick it with "+".
    func revealApp()
}

extension PermissionsChecking {
    func isGranted(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility: return isAccessibilityGranted
        case .screenRecording: return isScreenRecordingGranted
        }
    }

    /// Shows the system prompt (which also adds Lampo to the list) and opens the right Settings pane.
    /// For Screen Recording the pane opens only after the request, so Lampo is already in the list.
    func grant(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            requestAccessibility()
            openAccessibilitySettings()
        case .screenRecording:
            // On macOS 27 an app can't add itself to the Screen Recording list: the request makes
            // macOS show an alert whose "Open System Settings" button does that. Opening the pane at
            // the same time hid the alert behind a list without Lampo. So the pane is opened only
            // when no alert shows up (e.g. after "Don't Allow"), where Lampo is added with "+".
            Task {
                await requestScreenRecording()
                try? await Task.sleep(for: .milliseconds(800))
                if !isSystemPrivacyAlertShowing {
                    openScreenRecordingSettings()
                }
            }
        }
    }
}

@MainActor
final class PermissionsService: PermissionsChecking {
    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Note: macOS may only report a new Screen Recording grant after Lampo relaunches;
    /// System Settings offers "Quit & Reopen" when that's needed.
    var isScreenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt, which also adds Lampo to the Accessibility list.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// On macOS 27 `CGRequestScreenCaptureAccess()` alone is refused by TCC without a prompt
    /// ("does not allow prompting") and doesn't add Lampo to the list. Asking ScreenCaptureKit for
    /// the shareable content is what registers the app: it shows the system prompt and adds Lampo
    /// (switched off) to Privacy & Security › Screen & System Audio Recording.
    func requestScreenRecording() async {
        guard !isScreenRecordingGranted else { return }
        _ = CGRequestScreenCaptureAccess()
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            // Expected until the user allows it.
            Log.app.info("screen recording not allowed yet: \(error.localizedDescription, privacy: .public)")
        }
    }

    func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    /// The TCC alert is drawn by the `universalAccessAuthWarn` agent. Window owner names are
    /// readable without Screen Recording; only this name is checked.
    var isSystemPrivacyAlertShowing: Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains { ($0[kCGWindowOwnerName as String] as? String) == "universalAccessAuthWarn" }
    }

    func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
