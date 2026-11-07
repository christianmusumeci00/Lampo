import Foundation
import Observation

/// State of the Lens: one selection, a row of actions, a streamed preview.
@MainActor
@Observable
final class LensViewModel {
    enum Phase: Equatable {
        case streaming
        case done
        case failed(String)
    }

    let selection: SelectionContext
    let actions: [LampoAction]
    private(set) var activeIndex: Int
    private(set) var output = ""
    private(set) var phase: Phase = .streaming
    private(set) var route: ModelRoute = .onDevice
    private(set) var flash: String?

    @ObservationIgnored private let runner: ActionRunner
    @ObservationIgnored private let pasteboard: any PasteboardClient
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    /// Called with the final text when the user confirms Replace.
    @ObservationIgnored var onReplace: ((String) -> Void)?

    init(selection: SelectionContext, actions: [LampoAction], initialActionID: UUID,
         runner: ActionRunner, pasteboard: any PasteboardClient) {
        self.selection = selection
        self.actions = actions
        self.activeIndex = actions.firstIndex { $0.id == initialActionID } ?? 0
        self.runner = runner
        self.pasteboard = pasteboard
    }

    var activeAction: LampoAction? { actions.indices.contains(activeIndex) ? actions[activeIndex] : nil }
    var result: String { RewriteCleaner.clean(output, original: selection.text) }
    var isStreaming: Bool { phase == .streaming }
    var canReplace: Bool { phase == .done && !result.isEmpty }

    func start() { run() }

    func select(_ index: Int) {
        guard actions.indices.contains(index) else { return }
        activeIndex = index
        run()
    }

    func next() { select((activeIndex + 1) % max(actions.count, 1)) }
    func previous() { select((activeIndex - 1 + actions.count) % max(actions.count, 1)) }
    func retry() { run() }

    func cancel() {
        task?.cancel()
        task = nil
    }

    func copy() {
        guard !result.isEmpty else { return }
        pasteboard.setString(result)
        flash = String(localized: "Copied")
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.flash = nil
        }
    }

    func replace() {
        guard canReplace else { return }
        cancel()
        onReplace?(result)
    }

    private func run() {
        cancel()
        output = ""
        phase = .streaming
        guard let action = activeAction else { return }
        let context = runner.templateContext(selection: selection.text, clipboard: nil, app: selection.app?.name)
        let run: ActionRunner.Run
        do {
            run = try runner.start(action, context: context)
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? ModelError.other.localizedDescription)
            return
        }
        route = run.route
        task = Task { [weak self] in
            do {
                for try await text in run.stream {
                    self?.output = text
                }
                if !Task.isCancelled {
                    self?.phase = .done
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["LAMPO_QA_AUTOREPLACE"] == "1" {
                        try? await Task.sleep(for: .seconds(1.5))
                        self?.replace()
                    }
                    #endif
                }
            } catch is CancellationError {
                // A newer run replaced this one, or the Lens closed.
            } catch {
                guard !Task.isCancelled else { return }
                self?.phase = .failed((error as? LocalizedError)?.errorDescription ?? ModelError.other.localizedDescription)
            }
        }
    }
}
