import Foundation

/// Where a request runs.
enum ModelRoute: String, Codable, Sendable, CaseIterable, Hashable {
    case onDevice
    case privateCloud
}

/// How hard the model should think. Only meaningful on Private Cloud Compute.
enum ReasoningEffort: Sendable, Equatable {
    case light
    case deep
}

enum RoutingError: Error, Equatable, Sendable {
    /// "Only on this Mac" is on and the request asked explicitly for the cloud.
    case blockedByOnlyOnMac
    /// This build does not carry the Private Cloud Compute entitlement.
    case privateCloudNotInBuild
}

/// Decides the effective route for a request. Pure and testable.
struct RoutingPolicy: Sendable, Equatable {
    var onlyOnMac: Bool
    var privateCloudInBuild: Bool = BuildFeatures.isPrivateCloudCompiledIn

    /// - Parameters:
    ///   - requested: the route the action or button asked for.
    ///   - explicit: true when the user pressed a cloud-only control ("Think harder").
    ///     Explicit cloud requests fail loudly instead of silently staying on the Mac;
    ///     actions merely *configured* for the cloud fall back to on-device.
    func resolve(_ requested: ModelRoute, explicit: Bool) throws(RoutingError) -> ModelRoute {
        switch requested {
        case .onDevice:
            return .onDevice
        case .privateCloud:
            if onlyOnMac {
                if explicit { throw .blockedByOnlyOnMac }
                return .onDevice
            }
            if !privateCloudInBuild {
                if explicit { throw .privateCloudNotInBuild }
                return .onDevice
            }
            return .privateCloud
        }
    }

    /// Whether cloud-only controls should be enabled at all.
    var allowsPrivateCloud: Bool { !onlyOnMac && privateCloudInBuild }
}
