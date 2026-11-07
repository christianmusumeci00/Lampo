import AppKit
import ApplicationServices

/// Status and requests for the privacy permissions Lampo needs.
@MainActor
protocol PermissionsChecking: AnyObject {
    var isAccessibilityGranted: Bool { get }
    func requestAccessibility()
    func openAccessibilitySettings()
}

@MainActor
final class PermissionsService: PermissionsChecking {
    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt, which also adds Lampo to the Accessibility list.
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
