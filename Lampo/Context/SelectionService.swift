import AppKit

/// Reads the selection in the frontmost app: Accessibility first, then a ⌘C round-trip
/// through the clipboard (Electron, some web views), always restoring the clipboard.
@MainActor
protocol SelectionReading: AnyObject {
    /// - Parameter allowClipboardFallback: the ⌘C fallback costs up to ~150 ms and needs the
    ///   source app to have keyboard focus, so callers decide when it's acceptable.
    func readSelection(allowClipboardFallback: Bool) async -> SelectionContext?
}

@MainActor
final class SelectionService: SelectionReading {
    private let accessibility: any AccessibilityClient
    private let clipboard: ClipboardBridge
    private let frontmostApp: @MainActor () -> SourceApp?

    init(accessibility: any AccessibilityClient, clipboard: ClipboardBridge,
         frontmostApp: @escaping @MainActor () -> SourceApp? = { SourceApp.frontmost() }) {
        self.accessibility = accessibility
        self.clipboard = clipboard
        self.frontmostApp = frontmostApp
    }

    func readSelection(allowClipboardFallback: Bool) async -> SelectionContext? {
        guard accessibility.isTrusted, let app = frontmostApp() else { return nil }

        if let selection = accessibility.selection(in: app) {
            Log.context.debug("selection via AX (\(selection.text.count) chars)")
            return SelectionContext(text: selection.text, app: app,
                                    anchor: selection.bounds ?? accessibility.focusedElementBounds(in: app),
                                    element: selection.element, source: .accessibility)
        }

        guard allowClipboardFallback else { return nil }
        guard let text = await clipboard.copySelection(),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Log.context.debug("no selection")
            return nil
        }
        Log.context.debug("selection via clipboard (\(text.count) chars)")
        return SelectionContext(text: text, app: app, anchor: accessibility.focusedElementBounds(in: app),
                                element: nil, source: .clipboard)
    }
}
