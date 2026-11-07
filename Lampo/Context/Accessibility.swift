import AppKit
import ApplicationServices

/// The app the user is working in (never Lampo itself).
struct SourceApp: Equatable, Sendable {
    var name: String
    var bundleIdentifier: String?
    var processIdentifier: pid_t
    /// Electron/Chromium apps expose little through Accessibility.
    var isElectron: Bool

    @MainActor
    static func frontmost() -> SourceApp? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let electron = app.bundleURL.map {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path)
        } ?? false
        return SourceApp(name: app.localizedName ?? "", bundleIdentifier: app.bundleIdentifier,
                         processIdentifier: app.processIdentifier, isElectron: electron)
    }
}

/// A focused text element in another app. Opaque outside the Accessibility client.
final class AXElementHandle {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
}

/// Text selected in the frontmost app, as read through Accessibility.
struct AXSelection {
    var text: String
    /// Selection rectangle in Cocoa screen coordinates (origin bottom-left), when available.
    var bounds: CGRect?
    var element: AXElementHandle
}

/// Accessibility API access, abstracted for tests.
@MainActor
protocol AccessibilityClient: AnyObject {
    var isTrusted: Bool { get }
    func selection(in app: SourceApp) -> AXSelection?
    /// Bounds of the focused element (fallback anchor when the selection has none).
    func focusedElementBounds(in app: SourceApp) -> CGRect?
    /// Replaces the selected text of `element`. Returns false when the app doesn't support it,
    /// so the caller falls back to a paste.
    func replaceSelectedText(of element: AXElementHandle, with text: String) -> Bool
}

@MainActor
final class SystemAccessibilityClient: AccessibilityClient {
    private var electronEnabledPIDs: Set<pid_t> = []

    var isTrusted: Bool { AXIsProcessTrusted() }

    func selection(in app: SourceApp) -> AXSelection? {
        guard isTrusted, let element = focusedElement(in: app) else { return nil }
        if role(of: element) == (kAXSecureTextFieldSubrole as String) || subrole(of: element) == (kAXSecureTextFieldSubrole as String) {
            return nil   // never read password fields
        }
        guard let text: String = attribute(element, kAXSelectedTextAttribute),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return AXSelection(text: text, bounds: selectionBounds(of: element), element: AXElementHandle(element))
    }

    func focusedElementBounds(in app: SourceApp) -> CGRect? {
        guard isTrusted, let element = focusedElement(in: app) else { return nil }
        guard let positionValue: AXValue = attribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return Self.cocoaRect(fromAX: CGRect(origin: position, size: size))
    }

    func replaceSelectedText(of handle: AXElementHandle, with text: String) -> Bool {
        let element = handle.element
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue else { return false }
        // Web content often accepts the write without registering it for undo: paste instead.
        guard !isInsideWebArea(element) else { return false }

        let rangeBefore = selectedRange(of: element)
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else {
            return false
        }
        // Verify when the value is readable; some apps report success and change nothing.
        guard let range = rangeBefore, let value: String = attribute(element, kAXValueAttribute) else { return true }
        let nsValue = value as NSString
        let length = (text as NSString).length
        guard range.location + length <= nsValue.length else { return false }
        let written = nsValue.substring(with: NSRange(location: range.location, length: length))
        return Self.normalizedNewlines(written) == Self.normalizedNewlines(text)
    }

    // MARK: Private

    private func focusedElement(in app: SourceApp) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        if app.isElectron, !electronEnabledPIDs.contains(app.processIdentifier) {
            // Asks Electron to build its accessibility tree (it is lazy). Takes effect asynchronously.
            AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            electronEnabledPIDs.insert(app.processIdentifier)
        }
        guard let focused: AXUIElement = attribute(appElement, kAXFocusedUIElementAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(focused, 0.25)
        return focused
    }

    private func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value: AXValue = attribute(element, kAXSelectedTextRangeAttribute) else { return nil }
        var range = CFRange()
        return AXValueGetValue(value, .cfRange, &range) ? range : nil
    }

    private func selectionBounds(of element: AXUIElement) -> CGRect? {
        guard var range = selectedRange(of: element), range.length > 0,
              let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return nil }
        return Self.cocoaRect(fromAX: rect)
    }

    private func isInsideWebArea(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<25 {
            guard let node = current else { return false }
            if role(of: node) == "AXWebArea" { return true }
            current = attribute(node, kAXParentAttribute)
        }
        return false
    }

    private func role(of element: AXUIElement) -> String? { attribute(element, kAXRoleAttribute) }
    private func subrole(of element: AXUIElement) -> String? { attribute(element, kAXSubroleAttribute) }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        if T.self == AXUIElement.self {
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        } else if T.self == AXValue.self {
            guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        }
        return value as? T
    }

    /// Accessibility uses top-left-origin global coordinates; AppKit uses bottom-left.
    static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func normalizedNewlines(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
