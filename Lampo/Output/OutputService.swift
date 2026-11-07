import AppKit

/// Writes results back where the user is working.
@MainActor
final class OutputService {
    enum Method: Equatable {
        case accessibility
        case paste
    }

    private let accessibility: any AccessibilityClient
    private let clipboard: ClipboardBridge
    private let pasteboard: any PasteboardClient
    private let activate: @MainActor (SourceApp) async -> Void

    init(accessibility: any AccessibilityClient, clipboard: ClipboardBridge, pasteboard: any PasteboardClient,
         activate: @escaping @MainActor (SourceApp) async -> Void = OutputService.activateIfNeeded) {
        self.accessibility = accessibility
        self.clipboard = clipboard
        self.pasteboard = pasteboard
        self.activate = activate
    }

    /// Replaces the selection in its app as a single undoable edit (⌘Z restores it).
    /// Accessibility first; otherwise one ⌘V with the clipboard restored afterwards.
    @discardableResult
    func replaceSelection(_ text: String, in selection: SelectionContext) async -> Method {
        if let app = selection.app { await activate(app) }
        if let element = selection.element, accessibility.replaceSelectedText(of: element, with: text) {
            Log.output.info("replaced via AX")
            return .accessibility
        }
        await clipboard.paste(text)
        Log.output.info("replaced via paste")
        return .paste
    }

    /// Inserts at the cursor of the frontmost (or given) app with a single paste.
    func insert(_ text: String, into app: SourceApp?) async {
        if let app { await activate(app) }
        await clipboard.paste(text)
    }

    func copy(_ text: String) {
        pasteboard.setString(text)
    }

    /// Makes sure keystrokes reach the source app (e.g. after the user clicked elsewhere).
    static func activateIfNeeded(_ app: SourceApp) async {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier,
              let running = NSRunningApplication(processIdentifier: app.processIdentifier) else { return }
        running.activate()
        try? await Task.sleep(for: .milliseconds(120))
    }
}
