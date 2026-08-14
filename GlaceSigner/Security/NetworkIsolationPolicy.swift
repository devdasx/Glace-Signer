import Foundation

enum OfflineNetworkStatus: Equatable, Sendable {
    case checking
    case offline
    case wifiConnected
    case otherConnection

    var permitsSecretHandling: Bool {
        self == .offline
    }
}

enum NetworkIsolationPolicy {
    static func effectiveStatus(
        actualStatus: OfflineNetworkStatus,
        debugOverrideEnabled: Bool
    ) -> OfflineNetworkStatus {
#if DEBUG
        debugOverrideEnabled ? .offline : actualStatus
#else
        actualStatus
#endif
    }
}
