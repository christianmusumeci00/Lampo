import CoreGraphics
import Foundation

/// Availability of the on-device model, mirrored from `SystemLanguageModel.Availability`
/// so the rest of the app (and tests) does not depend on FoundationModels.
enum ModelAvailability: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown

    var isAvailable: Bool { self == .available }
}

/// A single user turn sent to the model: text, plus images (window screenshots)
/// placed before the text.
struct ModelPrompt: Sendable, Equatable {
    var text: String
    var images: [CGImage]

    init(_ text: String, images: [CGImage] = []) {
        self.text = text
        self.images = images
    }
}

/// Entry point to the language model. Implemented by `FoundationModelService`,
/// mocked in tests.
protocol ModelService: AnyObject, Sendable {
    func availability() -> ModelAvailability
    /// Context window of the route's model, in tokens.
    func contextSize(for route: ModelRoute) async -> Int
    /// Token count of `text` for the on-device model.
    func tokenCount(_ text: String) async throws -> Int
    /// Starts a multi-turn conversation. Throws if the route is not usable in this build.
    func makeConversation(route: ModelRoute, instructions: String) throws -> any ModelConversation
    /// Pulls an event's or reminder's words out of `text` with guided generation. Always on device.
    func extractDetails(from text: String, kind: DraftKind) async throws -> ExtractedDetails
}

/// A multi-turn session with the model.
///
/// Streaming contract: `stream(_:reasoning:)` yields the **cumulative** response text
/// (each element replaces the previous one), mirroring FoundationModels snapshots.
/// Cancelling the consuming task stops generation; the conversation stays usable
/// and keeps every turn that completed.
protocol ModelConversation: AnyObject, Sendable {
    var route: ModelRoute { get }
    func prewarm()
    func stream(_ prompt: ModelPrompt, reasoning: ReasoningEffort?) -> AsyncThrowingStream<String, Error>
}
