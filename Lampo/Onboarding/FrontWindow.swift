import AppKit

/// A window that opens above every other app, then behaves normally.
///
/// Lampo is an agent app: `NSApp.activate()` is only a request since macOS 14, and the system
/// can refuse it (on first launch it often does), which left the welcome window behind the app the
/// user was in. The window starts at the floating level, on the current Space (full-screen apps
/// included), and drops to the normal level once the user has it: System Settings, opened from it
/// to grant a permission, then comes in front as expected.
final class FrontWindow: NSWindow {
    private var lowersWhenKey = false

    /// Shows the window above everything and asks to activate Lampo.
    func presentAboveEverything() {
        level = .floating
        lowersWhenKey = true
        collectionBehavior.formUnion([.moveToActiveSpace, .fullScreenAuxiliary])
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }

    override func becomeKey() {
        super.becomeKey()
        guard lowersWhenKey else { return }
        lowersWhenKey = false
        level = .normal
    }
}
