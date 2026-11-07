import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView(state: state)
            }
            Tab("Shortcuts", systemImage: "keyboard") {
                ShortcutsSettingsView()
            }
            Tab("Privacy", systemImage: "lock") {
                PrivacySettingsView(preferences: state.preferences)
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsView()
            }
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralSettingsView: View {
    @Bindable var state: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?

    var body: some View {
        @Bindable var preferences = state.preferences
        Form {
            if !state.availability.isAvailable && state.availability != .unknown {
                Section {
                    AvailabilityView(availability: state.availability) { state.refreshAvailability() }
                }
            }
            Section {
                Toggle("Enabled", isOn: $state.isEnabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in setLaunchAtLogin(newValue) }
                if let launchAtLoginError {
                    Text(launchAtLoginError).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Picker("Panel position", selection: $preferences.panelPosition) {
                    Text("Center of the screen").tag(PanelPosition.center)
                    Text("Near the pointer").tag(PanelPosition.nearCursor)
                }
                Toggle("Close the panel after copying", isOn: $preferences.closePanelAfterCopy)
                Picker("Answer language", selection: $preferences.responseLanguage) {
                    Text("Same as the question").tag(ResponseLanguage.automatic)
                    Text("Italian").tag(ResponseLanguage.italian)
                    Text("English").tag(ResponseLanguage.english)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { state.refreshAvailability() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = String(localized: "Couldn't change the login item. Try again from System Settings › General › Login Items.")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open Lampo", name: .togglePanel)
            } footer: {
                Text("Works in every app, including full-screen ones.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Restore defaults") {
                    KeyboardShortcuts.reset(.togglePanel)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PrivacySettingsView: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Only on this Mac", isOn: $preferences.onlyOnMac)
            } footer: {
                Text("When on, Lampo never uses Private Cloud Compute: every request is answered by the model on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !BuildFeatures.isPrivateCloudCompiledIn {
                Section {
                    Label("Private Cloud Compute is not available in this build.", systemImage: "cloud")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 40))
                .foregroundStyle(DesignTokens.accent)
                .accessibilityHidden(true)
            Text("Lampo").font(.title2.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Your Mac's intelligence, one shortcut away.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }
}
