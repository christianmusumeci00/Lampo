import KeyboardShortcuts
import SwiftUI

@main
struct LampoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: appDelegate.state)
        } label: {
            Image(systemName: appDelegate.state.isEnabled ? "bolt.fill" : "bolt.slash")
                .accessibilityLabel(Text("Lampo"))
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(state: appDelegate.state)
        }
    }
}

struct MenuContent: View {
    @Bindable var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {} label: {
            Text("Lampo")
            Text(state.statusLine)
        }
        .disabled(true)
        .onAppear { state.refreshAvailability() }

        Divider()

        Toggle("Enabled", isOn: $state.isEnabled)

        Button("Open Lampo") { state.togglePanel() }
            .globalKeyboardShortcut(.togglePanel)
            .disabled(!state.isEnabled)

        Menu("Quick Actions") {
            ForEach(state.actionStore.actions) { action in
                Button {
                    state.perform(action)
                } label: {
                    Label(action.name, systemImage: action.symbol)
                }
                .globalKeyboardShortcut(action.shortcutName)
            }
        }
        .disabled(!state.isEnabled)

        Divider()

        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Lampo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
