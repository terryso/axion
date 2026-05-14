import SwiftUI
import Combine

@MainActor
final class StatusBarController: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var serverVersion: String?

    private let healthChecker = BackendHealthChecker()
    private let processManager = ServerProcessManager()

    var statusIcon: String {
        switch connectionState {
        case .disconnected:
            return "circle.dashed"
        case .connected:
            return "circle.fill"
        case .running:
            return "circle.circle"
        }
    }

    var statusTooltip: String {
        switch connectionState {
        case .disconnected:
            return "Axion — 未连接"
        case .connected:
            return "Axion — 就绪"
        case .running:
            return "Axion — 运行中"
        }
    }

    init() {
        healthChecker.$connectionState
            .assign(to: &$connectionState)

        healthChecker.$serverVersion
            .assign(to: &$serverVersion)

        startHealthChecking()
    }

    func startHealthChecking() {
        healthChecker.startChecking()
    }

    func startServer() {
        processManager.startServer(healthChecker: healthChecker)
    }

    func stopServer() {
        processManager.stopServer()
    }

    var isServerManagedByUs: Bool {
        processManager.isServerManagedByUs
    }
}
