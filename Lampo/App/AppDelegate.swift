import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !RuntimeEnvironment.isRunningTests else { return }
        state.start()
        Log.app.info("accessibility trusted: \(self.state.permissions.isAccessibilityGranted, privacy: .public)")
        #if DEBUG
        // `LAMPO_QA_ACTION=<action UUID>` runs an action shortly after launch;
        // `LAMPO_QA_AUTOREPLACE=1` then confirms the Lens as soon as the preview is ready.
        let environment = ProcessInfo.processInfo.environment
        if let id = environment["LAMPO_QA_ACTION"].flatMap(UUID.init(uuidString:)),
           let action = state.actionStore.action(id: id) {
            Task {
                try? await Task.sleep(for: .seconds(1))
                state.perform(action)
            }
        }
        // Manual QA helper: `LAMPO_OPEN_PANEL=1` opens the panel at launch.
        if ProcessInfo.processInfo.environment["LAMPO_OPEN_PANEL"] == "1" {
            state.togglePanel()
            // `LAMPO_QA_QUERY="..."` also submits a question.
            if let query = ProcessInfo.processInfo.environment["LAMPO_QA_QUERY"],
               let viewModel = state.panelController?.viewModel {
                viewModel.query = query
                viewModel.submit()
            }
        }
        #endif
    }
}
