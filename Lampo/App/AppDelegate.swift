import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !RuntimeEnvironment.isRunningTests else { return }
        state.start()
        #if DEBUG
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
