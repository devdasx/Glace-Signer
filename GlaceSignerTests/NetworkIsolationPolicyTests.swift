import Testing
#if SWIFT_PACKAGE
@testable import GlaceSignerCore
#else
@testable import GlaceSigner
#endif

struct NetworkIsolationPolicyTests {
    @Test
    func overrideBehaviorMatchesBuildConfiguration() {
        let actualStatuses: [OfflineNetworkStatus] = [
            .checking,
            .offline,
            .wifiConnected,
            .otherConnection
        ]

        for actualStatus in actualStatuses {
            #expect(
                NetworkIsolationPolicy.effectiveStatus(
                    actualStatus: actualStatus,
                    debugOverrideEnabled: false
                ) == actualStatus
            )

#if DEBUG
            #expect(
                NetworkIsolationPolicy.effectiveStatus(
                    actualStatus: actualStatus,
                    debugOverrideEnabled: true
                ) == .offline
            )
#else
            #expect(
                NetworkIsolationPolicy.effectiveStatus(
                    actualStatus: actualStatus,
                    debugOverrideEnabled: true
                ) == actualStatus
            )
#endif
        }
    }
}
