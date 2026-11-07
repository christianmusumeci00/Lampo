import AppKit
import ApplicationServices
import CoreGraphics

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
    func requestScreenRecording()
    func openScreenRecordingSettings()
}

extension PermissionsChecking {
    func isGranted(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility: return isAccessibilityGranted
        case .screenRecording: return isScreenRecordingGranted
        }
    }

    /// Shows the system prompt (which also adds Lampo to the list) and opens the right Settings pane.
    func grant(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            requestAccessibility()
            openAccessibilitySettings()
        case .screenRecording:
            requestScreenRecording()
            openScreenRecordingSettings()
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

    /// First call shows the system prompt and adds Lampo to the Screen Recording list.
    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
