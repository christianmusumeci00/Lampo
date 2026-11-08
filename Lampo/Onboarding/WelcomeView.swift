import AppKit
import KeyboardShortcuts
import SwiftUI

/// First launch: what Lampo does, the three shortcuts to remember, then the permissions.
struct WelcomeView: View {
    let availability: ModelAvailability
    let onDone: () -> Void
    @State private var showsPermissions = false

    var body: some View {
        Group {
            if showsPermissions {
                PermissionsView(style: .onboarding, onDone: onDone)
            } else {
                intro
            }
        }
        .padding(28)
        .frame(width: 540)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Lampo")
                        .font(.title2.weight(.semibold))
                    Text("Your Mac's intelligence, one shortcut away. On your text, your screen, your apps.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                WelcomeRow(shortcut: .togglePanel, symbol: "bolt.fill",
                           title: "Ask from anywhere",
                           detail: "Open the panel over any app. The answer starts right away, from the model on your Mac.")
                WelcomeRow(shortcut: BuiltInActions.shortcutName(for: BuiltInActions.rewriteID), symbol: "text.cursor",
                           title: "Rewrite where you are",
                           detail: "Select text and press an action's shortcut: Lampo previews the result and replaces it in place. ⌘Z undoes it.")
                WelcomeRow(shortcut: BuiltInActions.shortcutName(for: BuiltInActions.askScreenID), symbol: "macwindow",
                           title: "Ask about the screen",
                           detail: "Lampo looks at the window you're using and answers about it: an error, a chart, a form.")
            }

            Label {
                Text("Offline, free and private. Nothing leaves your Mac unless you ask for Private Cloud Compute, and Lampo always tells you where a request ran.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.fill")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if !availability.isAvailable {
                Label {
                    Text(availability.shortStatus)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.callout)
                .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Continue") { showsPermissions = true }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct WelcomeRow: View {
    let shortcut: KeyboardShortcuts.Name?
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DesignTokens.accent)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    if let keys = shortcut.flatMap(KeyboardShortcuts.getShortcut(for:))?.description {
                        Text(verbatim: keys)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(.quaternary))
                            .accessibilityLabel(Text("Shortcut \(keys)"))
                    }
                }
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Shows the welcome window once, on first launch.
@MainActor
final class WelcomeWindowController {
    private var window: FrontWindow?
    static let shownKey = "didShowWelcome"

    func showIfFirstLaunch(availability: ModelAvailability, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: Self.shownKey) else { return }
        defaults.set(true, forKey: Self.shownKey)
        show(availability: availability)
    }

    func show(availability: ModelAvailability) {
        if window == nil {
            let hosting = NSHostingController(rootView: WelcomeView(availability: availability) { [weak self] in
                self?.window?.close()
            })
            let window = FrontWindow(contentViewController: hosting)
            window.title = String(localized: "Welcome to Lampo")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        window?.presentAboveEverything()
    }
}
