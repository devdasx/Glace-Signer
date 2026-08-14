import Foundation
import Network

@MainActor
final class OfflineNetworkMonitor: ObservableObject {
    @Published private(set) var status: OfflineNetworkStatus = .checking
#if DEBUG
    @Published private(set) var isNetworkIsolationBypassed = false
#endif

    var effectiveStatus: OfflineNetworkStatus {
#if DEBUG
        NetworkIsolationPolicy.effectiveStatus(
            actualStatus: status,
            debugOverrideEnabled: isNetworkIsolationBypassed
        )
#else
        NetworkIsolationPolicy.effectiveStatus(
            actualStatus: status,
            debugOverrideEnabled: false
        )
#endif
    }

    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let generalMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(
        label: "com.devdasx.glace.signer.network-isolation"
    )
    private var wifiPathIsAvailable: Bool?
    private var generalPathIsAvailable: Bool?
    private var hasStarted = false

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        wifiMonitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.wifiPathIsAvailable = isAvailable
                self?.refreshStatus()
            }
        }
        generalMonitor.pathUpdateHandler = { [weak self] path in
            let isAvailable = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.generalPathIsAvailable = isAvailable
                self?.refreshStatus()
            }
        }
        wifiMonitor.start(queue: monitorQueue)
        generalMonitor.start(queue: monitorQueue)
    }

    func stop() {
        guard hasStarted else {
            return
        }
        wifiMonitor.cancel()
        generalMonitor.cancel()
        hasStarted = false
    }

#if DEBUG
    func setNetworkIsolationBypassed(_ isBypassed: Bool) {
        isNetworkIsolationBypassed = isBypassed
    }
#endif

    private func refreshStatus() {
        guard let wifiPathIsAvailable, let generalPathIsAvailable else {
            status = .checking
            return
        }

        if wifiPathIsAvailable {
            status = .wifiConnected
        } else if generalPathIsAvailable {
            status = .otherConnection
        } else {
            status = .offline
        }
    }
}
