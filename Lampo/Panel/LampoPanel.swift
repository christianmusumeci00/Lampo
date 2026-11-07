import AppKit

/// Spotlight-style floating panel: becomes key to receive typing without
/// activating Lampo, so the app underneath stays frontmost.
final class LampoPanel: NSPanel {
    /// Return true to consume a key-down event before normal dispatch.
    var keyDownHandler: ((NSEvent) -> Bool)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 160),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false            // drawn by SwiftUI around the rounded glass
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        setAccessibilityRole(.popover)
        setAccessibilityLabel(String(localized: "Lampo"))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let keyDownHandler, keyDownHandler(event) {
            return
        }
        super.sendEvent(event)
    }

    /// The text view currently editing, if any (the field editor of the input).
    var activeTextView: NSTextView? { firstResponder as? NSTextView }
}
