import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    /// Links that arrive before `start()` (a link that launches Lampo comes before didFinishLaunching).
    private var pendingURLs: [URL]? = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !RuntimeEnvironment.isRunningTests else { return }
        installURLHandler()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !RuntimeEnvironment.isRunningTests else { return }
        state.start()
        // Again, in case SwiftUI installed its own handler in between.
        installURLHandler()
        let queued = pendingURLs ?? []
        pendingURLs = nil
        if !queued.isEmpty {
            Task {
                // Let the menu bar item and the panel settle first.
                try? await Task.sleep(for: .milliseconds(300))
                queued.forEach(state.open)
            }
        }
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
                // With `LAMPO_QA_QUERY`, a panel action ("Ask the screen") also gets a question.
                if let query = environment["LAMPO_QA_QUERY"], let viewModel = state.panelController?.viewModel {
                    try? await Task.sleep(for: .seconds(2))
                    for _ in 0..<60 where viewModel.isGenerating { try? await Task.sleep(for: .milliseconds(500)) }
                    viewModel.query = query
                    viewModel.submit()
                }
            }
        }
        // `LAMPO_QA_DRAFT=event|reminder` + `LAMPO_QA_QUERY` opens the confirmation card for that text
        // (real model extraction, no selection read). Nothing is saved without pressing Add.
        if let kind = environment["LAMPO_QA_DRAFT"].flatMap(DraftKind.init(rawValue:)),
           let query = environment["LAMPO_QA_QUERY"] {
            Task {
                try? await Task.sleep(for: .seconds(1))
                state.panelController?.showDraft(kind, from: query)
            }
        }
        // `LAMPO_QA_EXTRACT=auto|contact|table|todos` + `LAMPO_QA_QUERY` opens the Extract card for that text.
        if let kind = environment["LAMPO_QA_EXTRACT"], let query = environment["LAMPO_QA_QUERY"] {
            Task {
                try? await Task.sleep(for: .seconds(1))
                state.panelController?.showExtraction(from: query)
                if let forced = ExtractKind(rawValue: kind) {
                    state.panelController?.viewModel.switchExtraction(to: forced)
                }
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

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        if pendingURLs != nil {
            pendingURLs?.append(url)
        } else {
            state.open(url)
        }
    }

    /// `lampo://ask?q=…`
    private func installURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }
}
