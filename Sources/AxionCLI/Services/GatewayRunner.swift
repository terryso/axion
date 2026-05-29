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

// MARK: - GatewayRunnerStatus

struct GatewayRunnerStatus: Sendable, Equatable, Codable {
    let state: String
    let activeTaskCount: Int
    let uptimeSeconds: Double
    let label: String
    let pid: Int?
    let tgConnected: String?
    let lastReviewAt: String?
    let lastCuratorAt: String?

    init(state: String, activeTaskCount: Int, uptimeSeconds: Double, label: String, pid: Int? = nil, tgConnected: String? = nil, lastReviewAt: String? = nil, lastCuratorAt: String? = nil) {
        self.state = state
        self.activeTaskCount = activeTaskCount
        self.uptimeSeconds = uptimeSeconds
        self.label = label
        self.pid = pid
        self.tgConnected = tgConnected
        self.lastReviewAt = lastReviewAt
        self.lastCuratorAt = lastCuratorAt
    }

    enum CodingKeys: String, CodingKey {
        case state = "status"
        case activeTaskCount = "active_tasks"
        case uptimeSeconds = "uptime_seconds"
        case label
        case pid
        case tgConnected = "tg_connected"
        case lastReviewAt = "last_review_at"
        case lastCuratorAt = "last_curator_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(String.self, forKey: .state)
        activeTaskCount = try container.decode(Int.self, forKey: .activeTaskCount)
        uptimeSeconds = try container.decode(Double.self, forKey: .uptimeSeconds)
        label = try container.decode(String.self, forKey: .label)
        pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        tgConnected = try container.decodeIfPresent(String.self, forKey: .tgConnected)
        lastReviewAt = try container.decodeIfPresent(String.self, forKey: .lastReviewAt)
        lastCuratorAt = try container.decodeIfPresent(String.self, forKey: .lastCuratorAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(activeTaskCount, forKey: .activeTaskCount)
        try container.encode(uptimeSeconds, forKey: .uptimeSeconds)
        try container.encode(label, forKey: .label)
        if let pid {
            try container.encode(pid, forKey: .pid)
        } else {
            try container.encodeNil(forKey: .pid)
        }
        if let tgConnected {
            try container.encode(tgConnected, forKey: .tgConnected)
        } else {
            try container.encodeNil(forKey: .tgConnected)
        }
        if let lastReviewAt {
            try container.encode(lastReviewAt, forKey: .lastReviewAt)
        } else {
            try container.encodeNil(forKey: .lastReviewAt)
        }
        if let lastCuratorAt {
            try container.encode(lastCuratorAt, forKey: .lastCuratorAt)
        } else {
            try container.encodeNil(forKey: .lastCuratorAt)
        }
    }
}

// MARK: - GatewayRunner Actor

actor GatewayRunner {
    enum State: String, Sendable {
        case created, running, stopping, stopped
    }

    private var _state: State = .created
    private var _activeTaskCount: Int = 0
    private let maxDrainSeconds: Int = 30
    private let server: any GatewayHTTPControlling

    private var startTime: ContinuousClock.Instant?
    private var _telegramAdapter: TelegramAdapter?
    private var _tgStatusProvider: (@Sendable () -> String?)?
    private var _reviewStatusProvider: (@Sendable () -> String?)?
    private var _curatorStatusProvider: (@Sendable () -> String?)?

    var currentState: State { _state }
    var activeTaskCount: Int { _activeTaskCount }
    var isAcceptingTasks: Bool { _state == .running }

    init(server: any GatewayHTTPControlling) {
        self.server = server
    }

    func start() async throws {
        guard _state == .created else { return }
        startTime = .now
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

        if let adapter = _telegramAdapter {
            await adapter.stop()
        }

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

    func getStatus() -> GatewayRunnerStatus {
        let uptime: Double
        if let startTime {
            let duration = ContinuousClock.now - startTime
            uptime = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        } else {
            uptime = 0
        }
        return GatewayRunnerStatus(
            state: _state.rawValue,
            activeTaskCount: _activeTaskCount,
            uptimeSeconds: uptime,
            label: "dev.axion.gateway",
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            tgConnected: _tgStatusProvider?(),
            lastReviewAt: _reviewStatusProvider?(),
            lastCuratorAt: _curatorStatusProvider?()
        )
    }

    func setTelegramAdapter(_ adapter: TelegramAdapter) {
        _telegramAdapter = adapter
    }

    func setStatusProviders(
        tgStatus: (@Sendable () -> String?)?,
        reviewStatus: (@Sendable () -> String?)?,
        curatorStatus: (@Sendable () -> String?)?
    ) {
        _tgStatusProvider = tgStatus
        _reviewStatusProvider = reviewStatus
        _curatorStatusProvider = curatorStatus
    }
}
