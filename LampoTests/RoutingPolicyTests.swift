import Testing
@testable import Lampo

struct RoutingPolicyTests {
    @Test func onDeviceAlwaysOnDevice() throws {
        let policy = RoutingPolicy(onlyOnMac: true, privateCloudInBuild: true)
        #expect(try policy.resolve(.onDevice, explicit: true) == .onDevice)
    }

    @Test func onlyOnMacBlocksExplicitCloud() {
        let policy = RoutingPolicy(onlyOnMac: true, privateCloudInBuild: true)
        #expect(throws: RoutingError.blockedByOnlyOnMac) {
            try policy.resolve(.privateCloud, explicit: true)
        }
        #expect(!policy.allowsPrivateCloud)
    }

    @Test func onlyOnMacKeepsConfiguredCloudActionsLocal() throws {
        let policy = RoutingPolicy(onlyOnMac: true, privateCloudInBuild: true)
        #expect(try policy.resolve(.privateCloud, explicit: false) == .onDevice)
    }

    @Test func cloudWhenAllowed() throws {
        let policy = RoutingPolicy(onlyOnMac: false, privateCloudInBuild: true)
        #expect(try policy.resolve(.privateCloud, explicit: true) == .privateCloud)
        #expect(policy.allowsPrivateCloud)
    }

    @Test func buildWithoutEntitlement() throws {
        let policy = RoutingPolicy(onlyOnMac: false, privateCloudInBuild: false)
        #expect(throws: RoutingError.privateCloudNotInBuild) {
            try policy.resolve(.privateCloud, explicit: true)
        }
        #expect(try policy.resolve(.privateCloud, explicit: false) == .onDevice)
    }
}
