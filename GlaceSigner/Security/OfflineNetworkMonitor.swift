import Foundation
import Network

enum OfflineNetworkStatus: Equatable, Sendable {
    case checking
    case offline
    case wifiConnected
    case otherConnection

    var permitsSecretHandling: Bool {
        self == .offline
    }
}

@MainActor
final class OfflineNetworkMonitor: ObservableObject {
    @Published private(set) var status: OfflineNetworkStatus = .checking

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
