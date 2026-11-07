import Foundation

/// Human-readable model errors (Italian and English via the String Catalog).
enum ModelError: Error, Equatable, Sendable, LocalizedError {
    case unavailable(ModelAvailability)
    case guardrail
    case refusal
    case contextExceeded
    case rateLimited
    case unsupportedLanguage
    case timeout
    case busy
    case network
    case quotaReached
    case cloudUnavailable
    case blockedByOnlyOnMac
    case privateCloudNotInBuild
    case emptyResponse
    /// The input had to be cut to fit the model, so writing the result over the
    /// whole selection would lose text.
    case tooLongToReplace
    case other

    init(_ routing: RoutingError) {
        switch routing {
        case .blockedByOnlyOnMac: self = .blockedByOnlyOnMac
        case .privateCloudNotInBuild: self = .privateCloudNotInBuild
        }
    }

    var errorDescription: String? {
        switch self {
        case .unavailable(let availability):
            return availability.message
        case .guardrail:
            return String(localized: "Apple's safety guidelines blocked this request. Try rephrasing it.")
        case .refusal:
            return String(localized: "The model declined to answer this request.")
        case .contextExceeded:
            return String(localized: "The text is too long for the on-device model. Try a shorter selection.")
        case .rateLimited:
            return String(localized: "The model is busy right now. Try again in a moment.")
        case .unsupportedLanguage:
            return String(localized: "The model does not support this language yet.")
        case .timeout:
            return String(localized: "The model took too long to answer. Try again.")
        case .busy:
            return String(localized: "Lampo is still answering the previous request.")
        case .network:
            return String(localized: "Private Cloud Compute could not be reached. Check your connection.")
        case .quotaReached:
            return String(localized: "You reached the Private Cloud Compute limit for now. Try again later.")
        case .cloudUnavailable:
            return String(localized: "Private Cloud Compute is not available right now.")
        case .blockedByOnlyOnMac:
            return String(localized: "“Only on this Mac” is on, so Lampo won't use Private Cloud Compute.")
        case .privateCloudNotInBuild:
            return String(localized: "Private Cloud Compute is not available in this build.")
        case .emptyResponse:
            return String(localized: "The model returned an empty answer. Try again.")
        case .tooLongToReplace:
            return String(localized: "The text is too long to rewrite in place on this Mac. Select a shorter part.")
        case .other:
            return String(localized: "Something went wrong while generating the answer.")
        }
    }
}

extension ModelAvailability {
    var message: String {
        switch self {
        case .available:
            return String(localized: "The model on this Mac is ready.")
        case .deviceNotEligible:
            return String(localized: "This Mac doesn't support Apple Intelligence.")
        case .appleIntelligenceNotEnabled:
            return String(localized: "Turn on Apple Intelligence in System Settings to use Lampo.")
        case .modelNotReady:
            return String(localized: "The model is still downloading. Lampo will be ready shortly.")
        case .unknown:
            return String(localized: "The on-device model is not available.")
        }
    }

    /// Short status line for the menu bar.
    var shortStatus: String {
        switch self {
        case .available: return String(localized: "Active · model on this Mac")
        case .modelNotReady: return String(localized: "Model downloading…")
        default: return String(localized: "Model not available")
        }
    }
}
