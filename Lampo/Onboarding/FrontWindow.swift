import AppKit
import SwiftUI

/// A window that opens above every other app, then behaves normally.
///
/// Lampo is an agent app: `NSApp.activate()` is only a request since macOS 14, and the system
/// can refuse it (on first launch it often does), which left the welcome window behind the app the
/// user was in. The window starts at the floating level, on the current Space (full-screen apps
/// included), and drops to the normal level once the user has it: System Settings, opened from it
/// to grant a permission, then comes in front as expected.
final class FrontWindow: NSWindow {
    private var lowersWhenKey = false

    /// A fixed-size window for `content`, centered on the screen the user is looking at.
    /// The size is fixed so SwiftUI can't move or resize it after it's been centered (with
    /// `NSHostingController` sizing, `center()` ran before the final size and the window ended
    /// up at the top of the screen).
    static func make(title: String, size: NSSize, content: some View) -> FrontWindow {
        let hosting = NSHostingController(rootView: content.frame(width: size.width, height: size.height))
        hosting.sizingOptions = []
        let window = FrontWindow(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentViewController = hosting
        window.setContentSize(size)
        window.title = title
        window.isReleasedWhenClosed = false
        window.centerOnActiveScreen()
        return window
    }

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

    /// Centers the window, exactly, in the visible part (no menu bar, no Dock) of the screen with
    /// the pointer, which is the one the user is looking at.
    func centerOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            center()
            return
        }
        setFrameOrigin(Self.centeredOrigin(for: frame.size, in: visible))
    }

    static func centeredOrigin(for size: NSSize, in visible: NSRect) -> NSPoint {
        NSPoint(x: (visible.midX - size.width / 2).rounded(),
                y: (visible.midY - size.height / 2).rounded())
    }
}

/// Gives Lampo a Dock icon while one of its guide windows is open, so the window can't get lost
/// behind System Settings: clicking the icon brings it back (`AppDelegate`). Lampo goes back to
/// being menu-bar only when the last of these windows closes.
@MainActor
final class DockPresence {
    static let shared = DockPresence()

    private var windows: [FrontWindow] = []
    private var observers: [ObjectIdentifier: any NSObjectProtocol] = [:]
    private let setPolicy: (NSApplication.ActivationPolicy) -> Void

    init(setPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) }) {
        self.setPolicy = setPolicy
    }

    var hasWindows: Bool { !windows.isEmpty }

    /// Call before showing `window`. Adding it again does nothing.
    func attach(_ window: FrontWindow) {
        let key = ObjectIdentifier(window)
        guard observers[key] == nil else { return }
        if windows.isEmpty { setPolicy(.regular) }
        windows.append(window)
        observers[key] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window else { return }
                self.detach(window)
            }
        }
    }

    func detach(_ window: FrontWindow) {
        let key = ObjectIdentifier(window)
        guard let observer = observers.removeValue(forKey: key) else { return }
        NotificationCenter.default.removeObserver(observer)
        windows.removeAll { $0 === window }
        if windows.isEmpty { setPolicy(.accessory) }
    }

    /// Brings the guide windows back in front. Returns false when there are none.
    @discardableResult
    func bringBack() -> Bool {
        guard !windows.isEmpty else { return false }
        windows.forEach { $0.presentAboveEverything() }
        return true
    }
}
