import ArgumentParser
import Foundation

import AxionCore

struct GatewayStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "查看 Gateway 状态"
    )

    nonisolated(unsafe) static var liveStatusFetcher: (@Sendable (Int) async -> GatewayRunnerStatus?)?

    func run() async throws {
        let logFileName = "gateway.log"
        let errLogFileName = "gateway.err.log"
        let service = DaemonService(
            label: "dev.axion.gateway",
            subcommand: "gateway start",
            logFileName: logFileName,
            errLogFileName: errLogFileName
        )
        let status = service.status()

        // Step 1: If running, try HTTP query for live runtime status
        if status.status == .running {
            let port = status.port ?? 4242
            let liveStatus: GatewayRunnerStatus?

            if let fetcher = Self.liveStatusFetcher {
                liveStatus = await fetcher(port)
            } else {
                liveStatus = try? await Self.queryHTTPStatus(port: port)
            }

            if let live = liveStatus {
                printLiveStatus(live, daemonStatus: status, logFileName: logFileName, errLogFileName: errLogFileName)
                return
            }
        }

        // Step 2: Fallback to DaemonService-level status
        printDaemonStatus(status, logFileName: logFileName, errLogFileName: errLogFileName)
    }

    private static func queryHTTPStatus(port: Int) async throws -> GatewayRunnerStatus {
        let url = URL(string: "http://127.0.0.1:\(port)/v1/gateway/status")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(GatewayRunnerStatus.self, from: data)
    }

    private func printLiveStatus(_ status: GatewayRunnerStatus, daemonStatus: DaemonStatus, logFileName: String, errLogFileName: String) {
        print("Gateway status: \(status.state)")
        if let pid = status.pid ?? daemonStatus.pid { print("  PID: \(pid)") }
        if let host = daemonStatus.host { print("  Host: \(host)") }
        if let port = daemonStatus.port { print("  Port: \(port)") }
        print("  Active tasks: \(status.activeTaskCount)")
        let uptime = Int(status.uptimeSeconds)
        print("  Uptime: \(uptime)s")
        print("  Label: \(status.label)")
        print("  Plist: \(daemonStatus.plistPath)")
        let logDir = ConfigManager.defaultConfigDirectory
        print("  Log: \((logDir as NSString).appendingPathComponent(logFileName))")
        print("  Error log: \((logDir as NSString).appendingPathComponent(errLogFileName))")
        let tgStatus = status.tgConnected ?? "(pending Epic 29/30)"
        print("  TG connection: \(tgStatus)")
        let reviewStatus = status.lastReviewAt ?? "(pending Epic 29/30)"
        print("  Last review: \(reviewStatus)")
        if let reviewSummary = status.lastReviewSummary {
            print("  Last review summary: \(reviewSummary)")
        }
        let curatorStatus = status.lastCuratorAt ?? "(pending Epic 29/30)"
        print("  Last curator: \(curatorStatus)")
    }

    private func printDaemonStatus(_ status: DaemonStatus, logFileName: String, errLogFileName: String) {
        switch status.status {
        case .running:
            print("Gateway status: running")
            if let pid = status.pid { print("  PID: \(pid)") }
            if let host = status.host { print("  Host: \(host)") }
            if let port = status.port { print("  Port: \(port)") }
        case .stopped:
            print("Gateway status: stopped")
            if let pid = status.pid { print("  Last PID: \(pid)") }
        case .notInstalled:
            print("Gateway status: not_installed")
            print("  Run 'axion gateway install' to install")
        }

        let logDir = ConfigManager.defaultConfigDirectory
        print("  Label: \(status.label)")
        print("  Plist: \(status.plistPath)")
        print("  Log: \((logDir as NSString).appendingPathComponent(logFileName))")
        print("  Error log: \((logDir as NSString).appendingPathComponent(errLogFileName))")
        print("  TG connection: (pending Epic 29/30)")
        print("  Last review: (pending Epic 29/30)")
        print("  Last curator: (pending Epic 29/30)")
    }
}
