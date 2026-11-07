import Foundation

enum RuntimeEnvironment {
    /// True when the app is hosting a unit-test bundle: skip hotkeys, panels and model warm-up.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

enum BuildFeatures {
    /// Private Cloud Compute requires the managed entitlement
    /// `com.apple.developer.private-cloud-compute`. FoundationModels traps
    /// (fatalError) on any PCC request without it, so PCC code is compiled
    /// only when the `LAMPO_PCC` compilation condition is set.
    static var isPrivateCloudCompiledIn: Bool {
        #if LAMPO_PCC
        true
        #else
        false
        #endif
    }
}
