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
    /// The selection was too long and only an excerpt was sent. Replace is then off,
    /// so a rewrite of the excerpt can't overwrite the whole text.
    private(set) var wasTruncated = false

    @ObservationIgnored private let runner: ActionRunner
    @ObservationIgnored private let pasteboard: any PasteboardClient
    @ObservationIgnored private let routingPolicy: RoutingPolicy
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    @ObservationIgnored private var flashTask: Task<Void, Never>?

    /// Called with the final text when the user confirms Replace.
    @ObservationIgnored var onReplace: ((String) -> Void)?
    /// Called when a run finishes, with the action and the cleaned result (for the history).
    @ObservationIgnored var onCompleted: ((LampoAction, String, ModelRoute) -> Void)?

    init(selection: SelectionContext, actions: [LampoAction], initialActionID: UUID,
         runner: ActionRunner, pasteboard: any PasteboardClient,
         routingPolicy: RoutingPolicy = RoutingPolicy(onlyOnMac: true, privateCloudInBuild: false)) {
        self.selection = selection
        self.routingPolicy = routingPolicy
        self.actions = actions
        self.activeIndex = actions.firstIndex { $0.id == initialActionID } ?? 0
        self.runner = runner
        self.pasteboard = pasteboard
    }

    var activeAction: LampoAction? { actions.indices.contains(activeIndex) ? actions[activeIndex] : nil }
    var result: String { RewriteCleaner.clean(output, original: selection.text) }
    var isStreaming: Bool { phase == .streaming }
    var canReplace: Bool { phase == .done && !result.isEmpty && !wasTruncated }
    /// "Think harder" is offered for long texts, when Private Cloud Compute is allowed.
    var canThinkHarder: Bool { wasTruncated && phase != .streaming && route == .onDevice && routingPolicy.allowsPrivateCloud }

    func start() { run() }

    func select(_ index: Int) {
        guard actions.indices.contains(index) else { return }
        activeIndex = index
        run()
    }

    func next() { select((activeIndex + 1) % max(actions.count, 1)) }
    func previous() { select((activeIndex - 1 + actions.count) % max(actions.count, 1)) }
    func retry() { run() }

    /// Runs the action again on Private Cloud Compute, whose larger window fits more text.
    func thinkHarder() {
        guard canThinkHarder else { return }
        run(routeOverride: .privateCloud)
    }

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

    private func run(routeOverride: ModelRoute? = nil) {
        cancel()
        output = ""
        phase = .streaming
        wasTruncated = false
        guard let action = activeAction else { return }
        let context = runner.templateContext(selection: selection.text, clipboard: nil, app: selection.app?.name)
        task = Task { [weak self, runner] in
            do {
                let run = try await runner.start(action, context: context, routeOverride: routeOverride)
                guard !Task.isCancelled else { return }
                self?.route = run.route
                self?.wasTruncated = run.wasTruncated
                for try await text in run.stream {
                    self?.output = text
                }
                if !Task.isCancelled, let self {
                    self.phase = .done
                    self.onCompleted?(action, self.result, run.route)
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["LAMPO_QA_AUTOREPLACE"] == "1" {
                        try? await Task.sleep(for: .seconds(1.5))
                        self.replace()
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
