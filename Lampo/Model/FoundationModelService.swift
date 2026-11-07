import Foundation
import FoundationModels
import Synchronization

/// `ModelService` backed by Apple's FoundationModels framework, called in-process:
/// no server, no ports, no child processes.
final class FoundationModelService: ModelService {
    init() {}

    func availability() -> ModelAvailability {
        Self.map(SystemLanguageModel.default.availability)
    }

    func contextSize(for route: ModelRoute) async -> Int {
        switch route {
        case .onDevice:
            return SystemLanguageModel.default.contextSize
        case .privateCloud:
            #if LAMPO_PCC
            return (try? await PrivateCloudComputeLanguageModel().contextSize) ?? SystemLanguageModel.default.contextSize
            #else
            return SystemLanguageModel.default.contextSize
            #endif
        }
    }

    func tokenCount(_ text: String) async throws -> Int {
        try await SystemLanguageModel.default.tokenCount(for: text)
    }

    func makeConversation(route: ModelRoute, instructions: String) throws -> any ModelConversation {
        switch route {
        case .onDevice:
            return FoundationModelConversation(route: .onDevice, instructions: instructions) { transcript in
                if let transcript {
                    LanguageModelSession(model: SystemLanguageModel.default, transcript: transcript)
                } else {
                    LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
                }
            }
        case .privateCloud:
            #if LAMPO_PCC
            return FoundationModelConversation(route: .privateCloud, instructions: instructions) { transcript in
                if let transcript {
                    LanguageModelSession(model: PrivateCloudComputeLanguageModel(), transcript: transcript)
                } else {
                    LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
                }
            }
            #else
            throw ModelError.privateCloudNotInBuild
            #endif
        }
    }

    static func map(_ availability: SystemLanguageModel.Availability) -> ModelAvailability {
        switch availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        case .unavailable:
            return .unknown
        }
    }
}

/// Wraps a `LanguageModelSession`.
///
/// FoundationModels quirk (verified on macOS 27): cancelling a stream ends it without
/// throwing, and leaves the session unable to answer again ("Session ended without
/// producing a response"). So after each completed turn we keep the transcript, and
/// after a cancellation or failure we rebuild the session from it.
final class FoundationModelConversation: ModelConversation {
    typealias SessionFactory = @Sendable (Transcript?) -> LanguageModelSession

    let route: ModelRoute
    private let makeSession: SessionFactory
    private let state: Mutex<State>

    private struct State {
        var session: LanguageModelSession
        var lastGoodTranscript: Transcript?
        var needsRebuild = false
    }

    init(route: ModelRoute, instructions: String, makeSession: @escaping SessionFactory) {
        self.route = route
        self.makeSession = makeSession
        self.state = Mutex(State(session: makeSession(nil)))
    }

    func prewarm() {
        state.withLock { $0.session }.prewarm()
    }

    func stream(_ prompt: ModelPrompt, reasoning: ReasoningEffort?) -> AsyncThrowingStream<String, Error> {
        let session = currentSession()
        let contextOptions = Self.contextOptions(route: route, reasoning: reasoning)
        let text = prompt.text
        let started = ContinuousClock.now

        return AsyncThrowingStream { continuation in
            let task = Task {
                var produced = false
                do {
                    let stream = session.streamResponse(to: text, contextOptions: contextOptions)
                    for try await snapshot in stream {
                        if !produced {
                            produced = true
                            Log.model.debug("first token after \(started.duration(to: .now), privacy: .public)")
                        }
                        continuation.yield(snapshot.content)
                    }
                    if Task.isCancelled {
                        self.markNeedsRebuild()
                        continuation.finish(throwing: CancellationError())
                    } else if !produced {
                        self.markNeedsRebuild()
                        continuation.finish(throwing: ModelError.emptyResponse)
                    } else {
                        self.commit(session)
                        continuation.finish()
                    }
                } catch is CancellationError {
                    self.markNeedsRebuild()
                    continuation.finish(throwing: CancellationError())
                } catch {
                    self.markNeedsRebuild()
                    let mapped = Self.map(error)
                    Log.model.error("generation failed: \(String(describing: mapped), privacy: .public)")
                    continuation.finish(throwing: mapped)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func currentSession() -> LanguageModelSession {
        state.withLock { state in
            if state.needsRebuild {
                state.session = makeSession(state.lastGoodTranscript)
                state.needsRebuild = false
            }
            return state.session
        }
    }

    private func commit(_ session: LanguageModelSession) {
        let transcript = session.transcript
        state.withLock { $0.lastGoodTranscript = transcript }
    }

    private func markNeedsRebuild() {
        state.withLock { $0.needsRebuild = true }
    }

    private static func contextOptions(route: ModelRoute, reasoning: ReasoningEffort?) -> ContextOptions {
        guard route == .privateCloud, let reasoning else { return ContextOptions() }
        switch reasoning {
        case .light: return ContextOptions(reasoningLevel: .light)
        case .deep: return ContextOptions(reasoningLevel: .deep)
        }
    }

    static func map(_ error: any Error) -> ModelError {
        if let error = error as? ModelError { return error }
        if let error = error as? LanguageModelError {
            switch error {
            case .contextSizeExceeded: return .contextExceeded
            case .rateLimited: return .rateLimited
            case .guardrailViolation: return .guardrail
            case .refusal: return .refusal
            case .unsupportedLanguageOrLocale: return .unsupportedLanguage
            case .timeout: return .timeout
            default: return .other
            }
        }
        if let error = error as? SystemLanguageModel.Error {
            switch error {
            case .assetsUnavailable: return .unavailable(.modelNotReady)
            default: return .other
            }
        }
        if let error = error as? LanguageModelSession.Error {
            switch error {
            case .concurrentRequests: return .busy
            default: return .other
            }
        }
        if let error = error as? PrivateCloudComputeLanguageModel.Error {
            switch error {
            case .networkFailure: return .network
            case .quotaLimitReached: return .quotaReached
            case .serviceUnavailable: return .cloudUnavailable
            @unknown default: return .cloudUnavailable
            }
        }
        return .other
    }
}
