import Foundation
import Hummingbird
import OpenAgentSDK

import AxionCore

// MARK: - GatewayHTTPControlling Protocol

/// Protocol abstracting the HTTP server for testability.
protocol GatewayHTTPControlling: Sendable {
    func start() async throws
    func stop() async
}

// MARK: - AgentHTTPServer Conformance

extension AgentHTTPServer: GatewayHTTPControlling {}

// MARK: - GatewayRunner Actor

actor GatewayRunner {
    enum State: String, Sendable {
        case created, running, stopping, stopped
    }

    private var _state: State = .created
    private var _activeTaskCount: Int = 0
    private let maxDrainSeconds: Int = 30
    private let server: any GatewayHTTPControlling

    var currentState: State { _state }
    var activeTaskCount: Int { _activeTaskCount }
    var isAcceptingTasks: Bool { _state == .running }

    init(server: any GatewayHTTPControlling) {
        self.server = server
    }

    func start() async throws {
        guard _state == .created else { return }
        _state = .running
        do {
            try await server.start()
        } catch {
            _state = .stopped
            throw error
        }
        _state = .stopped
    }

    func stop(graceful: Bool) async {
        guard _state == .running else { return }
        _state = .stopping

        if graceful && _activeTaskCount > 0 {
            let deadline = ContinuousClock.now + .seconds(maxDrainSeconds)
            while _activeTaskCount > 0 {
                if ContinuousClock.now > deadline { break }
                try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
            }
        }

        await server.stop()
        _state = .stopped
    }

    func taskStarted() {
        _activeTaskCount += 1
    }

    func taskFinished() {
        if _activeTaskCount > 0 {
            _activeTaskCount -= 1
        }
    }
}
