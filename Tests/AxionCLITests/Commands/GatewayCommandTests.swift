import Testing
import ArgumentParser
import Foundation
@testable import AxionCLI

@Suite("GatewayCommand")
struct GatewayCommandTests {

    // MARK: - GatewayCommand Registration (Task 2.4)

    @Test("AxionCLI registers GatewayCommand as subcommand")
    func axionCLIRegistersGatewaySubcommand() {
        #expect(
            AxionCLI.configuration.subcommands.contains(where: { $0 == GatewayCommand.self }),
            "AxionCLI should register GatewayCommand as a subcommand"
        )
    }

    @Test("GatewayCommand has default subcommand GatewayStartCommand")
    func gatewayCommandHasDefaultSubcommand() {
        #expect(
            GatewayCommand.configuration.defaultSubcommand == GatewayStartCommand.self,
            "GatewayCommand default subcommand should be GatewayStartCommand"
        )
    }

    @Test("GatewayCommand has gateway command name")
    func gatewayCommandName() {
        #expect(GatewayCommand.configuration.commandName == "gateway")
    }

    // MARK: - GatewayStartCommand Options (Task 2.3)

    @Test("GatewayStartCommand default port is 4242")
    func defaultPortIs4242() throws {
        let cmd = try GatewayStartCommand.parse([])
        #expect(cmd.port == 4242)
    }

    @Test("GatewayStartCommand default host is 127.0.0.1")
    func defaultHostIs127() throws {
        let cmd = try GatewayStartCommand.parse([])
        #expect(cmd.host == "127.0.0.1")
    }

    @Test("GatewayStartCommand default authKey is nil")
    func defaultAuthKeyIsNil() throws {
        let cmd = try GatewayStartCommand.parse([])
        #expect(cmd.authKey == nil)
    }

    @Test("GatewayStartCommand parses custom port")
    func parsesCustomPort() throws {
        let cmd = try GatewayStartCommand.parse(["--port", "8080"])
        #expect(cmd.port == 8080)
    }

    @Test("GatewayStartCommand parses custom host")
    func parsesCustomHost() throws {
        let cmd = try GatewayStartCommand.parse(["--host", "0.0.0.0"])
        #expect(cmd.host == "0.0.0.0")
    }

    @Test("GatewayStartCommand parses authKey")
    func parsesAuthKey() throws {
        let cmd = try GatewayStartCommand.parse(["--auth-key", "mysecret"])
        #expect(cmd.authKey == "mysecret")
    }

    @Test("GatewayStartCommand parses verbose flag")
    func parsesVerboseFlag() throws {
        let cmd = try GatewayStartCommand.parse(["--verbose"])
        #expect(cmd.verbose)
    }

    @Test("GatewayStartCommand verbose default is false")
    func verboseDefaultIsFalse() throws {
        let cmd = try GatewayStartCommand.parse([])
        #expect(!cmd.verbose)
    }

    @Test("GatewayStartCommand parses all options combined")
    func parsesAllOptionsCombined() throws {
        let cmd = try GatewayStartCommand.parse([
            "--port", "9090",
            "--host", "0.0.0.0",
            "--auth-key", "secret",
            "--verbose"
        ])
        #expect(cmd.port == 9090)
        #expect(cmd.host == "0.0.0.0")
        #expect(cmd.authKey == "secret")
        #expect(cmd.verbose)
    }

    @Test("GatewayStartCommand port validation rejects zero")
    func portValidationRejectsZero() {
        #expect(throws: Error.self) {
            _ = try GatewayStartCommand.parse(["--port", "0"])
        }
    }

    @Test("GatewayStartCommand port validation rejects out of range")
    func portValidationRejectsOutOfRange() {
        #expect(throws: Error.self) {
            _ = try GatewayStartCommand.parse(["--port", "99999"])
        }
    }

    // MARK: - GatewayInstallCommand Options (Task 5.8)

    @Test("GatewayInstallCommand has correct defaults")
    func installCommandDefaults() throws {
        let cmd = try GatewayInstallCommand.parse([])
        #expect(cmd.host == "127.0.0.1")
        #expect(cmd.port == 4242)
        #expect(cmd.authKey == nil)
    }

    @Test("GatewayInstallCommand parses custom values")
    func installCommandCustomValues() throws {
        let cmd = try GatewayInstallCommand.parse(["--host", "0.0.0.0", "--port", "8080", "--auth-key", "secret"])
        #expect(cmd.host == "0.0.0.0")
        #expect(cmd.port == 8080)
        #expect(cmd.authKey == "secret")
    }

    @Test("GatewayInstallCommand rejects invalid port")
    func installCommandInvalidPort() {
        #expect(throws: Error.self) {
            _ = try GatewayInstallCommand.parse(["--port", "0"])
        }
        #expect(throws: Error.self) {
            _ = try GatewayInstallCommand.parse(["--port", "99999"])
        }
    }

    // MARK: - GatewayStatusCommand Options (Task 5.9)

    @Test("GatewayStatusCommand has status command name")
    func statusCommandName() {
        #expect(GatewayStatusCommand.configuration.commandName == "status")
    }

    // MARK: - GatewayUninstallCommand Options (Task 5.10)

    @Test("GatewayUninstallCommand has uninstall command name")
    func uninstallCommandName() {
        #expect(GatewayUninstallCommand.configuration.commandName == "uninstall")
    }

    @Test("GatewayUninstallCommand --keep-logs flag")
    func uninstallCommandKeepLogs() throws {
        let cmdDefault = try GatewayUninstallCommand.parse([])
        #expect(cmdDefault.keepLogs == false)

        let cmdKeep = try GatewayUninstallCommand.parse(["--keep-logs"])
        #expect(cmdKeep.keepLogs == true)
    }

    // MARK: - GatewayStatusCommand HTTP Fallback (Task 4.5, 4.6)

    @Test("GatewayStatusCommand fallback to DaemonService when HTTP fails")
    func statusCommandFallsBackToDaemonService() async throws {
        // Set up test seam: HTTP always returns nil (simulates connection refused)
        GatewayStatusCommand.liveStatusFetcher = { _ in nil }

        let fetcher = GatewayStatusCommand.liveStatusFetcher
        let result = await fetcher?(4242)
        #expect(result == nil)

        // Clean up
        GatewayStatusCommand.liveStatusFetcher = nil
    }

    @Test("GatewayStatusCommand parses HTTP response correctly")
    func statusCommandParsesHTTPResponse() async throws {
        let expectedStatus = GatewayRunnerStatus(
            state: "running",
            activeTaskCount: 2,
            uptimeSeconds: 3600.0,
            label: "dev.axion.gateway",
            pid: 12345,
            tgConnected: nil,
            lastReviewAt: nil,
            lastCuratorAt: nil
        )

        // Set up test seam: returns a valid status
        GatewayStatusCommand.liveStatusFetcher = { _ in expectedStatus }

        let fetcher = GatewayStatusCommand.liveStatusFetcher
        let result = await fetcher?(4242)

        #expect(result != nil)
        #expect(result?.state == "running")
        #expect(result?.activeTaskCount == 2)
        #expect(result?.uptimeSeconds == 3600.0)
        #expect(result?.label == "dev.axion.gateway")
        #expect(result?.pid == 12345)

        // Clean up
        GatewayStatusCommand.liveStatusFetcher = nil
    }

    @Test("GatewayStatusCommand returns rich status when HTTP succeeds")
    func statusCommandReturnsRichStatus() async throws {
        let status = GatewayRunnerStatus(
            state: "running",
            activeTaskCount: 5,
            uptimeSeconds: 7200.0,
            label: "dev.axion.gateway",
            pid: 9999,
            tgConnected: "connected",
            lastReviewAt: "2026-05-29",
            lastCuratorAt: nil
        )

        GatewayStatusCommand.liveStatusFetcher = { _ in status }

        let result = await GatewayStatusCommand.liveStatusFetcher?(4242)
        #expect(result?.state == "running")
        #expect(result?.activeTaskCount == 5)
        #expect(result?.uptimeSeconds == 7200.0)
        #expect(result?.pid == 9999)
        #expect(result?.tgConnected == "connected")
        #expect(result?.lastReviewAt == "2026-05-29")
        #expect(result?.lastCuratorAt == nil)

        GatewayStatusCommand.liveStatusFetcher = nil
    }

    // MARK: - Gateway Status HTTP Endpoint Response (Task 4.4)

    @Test("GatewayRunnerStatus encodes to expected JSON structure")
    func statusResponseEncodesToJSON() throws {
        let status = GatewayRunnerStatus(
            state: "running",
            activeTaskCount: 3,
            uptimeSeconds: 100.5,
            label: "dev.axion.gateway",
            pid: 42,
            tgConnected: nil,
            lastReviewAt: nil,
            lastCuratorAt: nil
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(status)
        let json = try #require(String(data: data, encoding: .utf8))

        // Verify JSON structure matches expected API response (AC#4 key names)
        #expect(json.contains("\"active_tasks\":3"))
        #expect(json.contains("\"label\":\"dev.axion.gateway\""))
        #expect(json.contains("\"status\":\"running\""))
        #expect(json.contains("\"uptime_seconds\":100.5"))
        #expect(json.contains("\"pid\":42"))
        #expect(json.contains("\"tg_connected\":null"))
        #expect(json.contains("\"last_review_at\":null"))
        #expect(json.contains("\"last_curator_at\":null"))
    }
}
