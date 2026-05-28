import Testing
import Foundation
@testable import AxionCLI

private final class GatewayLaunchctlCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []

    func append(_ args: [String]) {
        lock.lock()
        _calls.append(args)
        lock.unlock()
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }
}

@Suite("GatewayDaemonService")
struct GatewayDaemonTests {

    private func makeGatewayService(
        plistPath: String = "/tmp/test-gateway-\(UUID().uuidString)/dev.axion.gateway.plist",
        launchctlOutput: @escaping @Sendable ([String]) throws -> String = { _ in "" }
    ) -> DaemonService {
        DaemonService(
            label: "dev.axion.gateway",
            subcommand: "gateway start",
            logFileName: "gateway.log",
            errLogFileName: "gateway.err.log",
            keepAliveCrashOnly: true,
            environmentVariables: nil,
            plistPath: plistPath,
            runLaunchctl: launchctlOutput,
            resolveBin: { "/usr/local/bin/axion" }
        )
    }

    // MARK: - 5.1: Gateway label in plist

    @Test("Gateway plist uses dev.axion.gateway label")
    func gatewayPlistLabel() {
        let service = makeGatewayService()
        let xml = service.buildPlist()

        #expect(xml.contains("<key>Label</key>"))
        #expect(xml.contains("<string>dev.axion.gateway</string>"))
        #expect(!xml.contains("dev.axion.server"))
    }

    // MARK: - 5.2: KeepAlive is crash-only

    @Test("Gateway plist has KeepAlive with Crashed=true, not plain true")
    func gatewayKeepAliveCrashOnly() {
        let service = makeGatewayService()
        let xml = service.buildPlist()

        // Should contain crash-only KeepAlive
        #expect(xml.contains("<key>KeepAlive</key>"))
        #expect(xml.contains("<key>Crashed</key>"))
        #expect(xml.contains("<true/>"))

        // Verify the KeepAlive section is a dict, not just <true/>
        // Find the KeepAlive section and verify it's followed by <dict>
        let keepAliveRange = xml.range(of: "<key>KeepAlive</key>")!
        let afterKeepAlive = xml[keepAliveRange.upperBound...]
        #expect(afterKeepAlive.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<dict>"))
    }

    // MARK: - 5.3: ProgramArguments uses "gateway" "start"

    @Test("Gateway plist ProgramArguments contains gateway start subcommand")
    func gatewayProgramArguments() {
        let service = makeGatewayService()
        let xml = service.buildPlist()

        #expect(xml.contains("<string>gateway</string>"))
        #expect(xml.contains("<string>start</string>"))
        // Should NOT contain "server" as subcommand
        let lines = xml.components(separatedBy: "\n")
        let programArgsSection = lines.drop(while: { !$0.contains("ProgramArguments") })
        let argsContent = programArgsSection.prefix(while: { !$0.contains("</array>") }).joined()
        #expect(!argsContent.contains("<string>server</string>"))
    }

    // MARK: - 5.4: Gateway log paths

    @Test("Gateway plist log paths are gateway.log and gateway.err.log")
    func gatewayLogPaths() {
        let service = makeGatewayService()
        let xml = service.buildPlist()

        #expect(xml.contains("gateway.log"))
        #expect(xml.contains("gateway.err.log"))
        #expect(!xml.contains("server.log"))
        #expect(!xml.contains("server.err.log"))
    }

    // MARK: - 5.5: TG environment variables

    @Test("Gateway plist includes TG environment variables when set")
    func gatewayTgEnvVars() {
        let service = DaemonService(
            label: "dev.axion.gateway",
            subcommand: "gateway start",
            logFileName: "gateway.log",
            errLogFileName: "gateway.err.log",
            keepAliveCrashOnly: true,
            environmentVariables: [
                "AXION_TELEGRAM_BOT_TOKEN": "test-token-123",
                "AXION_TELEGRAM_ALLOWED_USERS": "user1,user2"
            ],
            plistPath: "/tmp/test.plist",
            runLaunchctl: { _ in "" },
            resolveBin: { "/usr/local/bin/axion" }
        )
        let xml = service.buildPlist()

        #expect(xml.contains("<key>AXION_TELEGRAM_BOT_TOKEN</key>"))
        #expect(xml.contains("<string>test-token-123</string>"))
        #expect(xml.contains("<key>AXION_TELEGRAM_ALLOWED_USERS</key>"))
        #expect(xml.contains("<string>user1,user2</string>"))
    }

    @Test("Gateway plist without TG env vars omits extra environment variables")
    func gatewayNoTgEnvVars() {
        let service = makeGatewayService()
        let xml = service.buildPlist(authKey: nil)

        #expect(!xml.contains("AXION_TELEGRAM_BOT_TOKEN"))
        #expect(!xml.contains("AXION_TELEGRAM_ALLOWED_USERS"))
    }

    @Test("Gateway plist with authKey and TG env vars includes all in EnvironmentVariables")
    func gatewayAuthKeyAndTgEnvVars() {
        let service = DaemonService(
            label: "dev.axion.gateway",
            subcommand: "gateway start",
            logFileName: "gateway.log",
            errLogFileName: "gateway.err.log",
            keepAliveCrashOnly: true,
            environmentVariables: ["AXION_TELEGRAM_BOT_TOKEN": "tok"],
            plistPath: "/tmp/test.plist",
            runLaunchctl: { _ in "" },
            resolveBin: { "/usr/local/bin/axion" }
        )
        let xml = service.buildPlist(authKey: "my-auth-key")

        #expect(xml.contains("<key>AXION_AUTH_KEY</key>"))
        #expect(xml.contains("<string>my-auth-key</string>"))
        #expect(xml.contains("<key>AXION_TELEGRAM_BOT_TOKEN</key>"))
        #expect(xml.contains("<string>tok</string>"))
    }

    // MARK: - 5.6: AXION_BIN resolution

    @Test("Gateway plist uses resolved AXION_BIN path")
    func gatewayAxiomBinResolution() {
        let service = DaemonService(
            label: "dev.axion.gateway",
            subcommand: "gateway start",
            logFileName: "gateway.log",
            errLogFileName: "gateway.err.log",
            keepAliveCrashOnly: true,
            plistPath: "/tmp/test.plist",
            runLaunchctl: { _ in "" },
            resolveBin: { "/custom/path/to/axion" }
        )
        let xml = service.buildPlist()

        #expect(xml.contains("<string>/custom/path/to/axion</string>"))
    }

    // MARK: - 5.7: Daemon regression — default params produce identical output

    @Test("Default DaemonService produces daemon-style plist (regression)")
    func daemonRegression() {
        let service = DaemonService(
            plistPath: "/tmp/test.plist",
            runLaunchctl: { _ in "" },
            resolveBin: { "/usr/local/bin/axion" }
        )
        let xml = service.buildPlist()

        // Should use daemon label
        #expect(xml.contains("<string>dev.axion.server</string>"))
        // Should use "server" subcommand
        #expect(xml.contains("<string>server</string>"))
        // Should use server.log paths
        #expect(xml.contains("server.log"))
        #expect(xml.contains("server.err.log"))
        // Should NOT have crash-only KeepAlive (should have plain <true/>)
        let keepAliveRange = xml.range(of: "<key>KeepAlive</key>")!
        let afterKeepAlive = xml[keepAliveRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(afterKeepAlive.hasPrefix("<true/>"))
        // Should NOT have Crashed key
        #expect(!xml.contains("<key>Crashed</key>"))
    }

    // MARK: - Install/Uninstall/Status with gateway params

    @Test("Gateway install writes correct plist and calls launchctl")
    func gatewayInstallWritesPlist() throws {
        let tempDir = NSTemporaryDirectory() + "axion-test-gw-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let plistPath = (tempDir as NSString).appendingPathComponent("dev.axion.gateway.plist")
        let collector = GatewayLaunchctlCollector()

        let service = DaemonService(
            label: "dev.axion.gateway",
            subcommand: "gateway start",
            logFileName: "gateway.log",
            errLogFileName: "gateway.err.log",
            keepAliveCrashOnly: true,
            plistPath: plistPath,
            runLaunchctl: { args in
                collector.append(args)
                return ""
            },
            resolveBin: { "/usr/local/bin/axion" }
        )

        _ = try service.install(host: "0.0.0.0", port: 9090, authKey: "gw-key")

        #expect(FileManager.default.fileExists(atPath: plistPath))
        let content = try String(contentsOfFile: plistPath, encoding: .utf8)
        #expect(content.contains("dev.axion.gateway"))
        #expect(content.contains("gateway"))
        #expect(content.contains("start"))
        #expect(content.contains("9090"))
        #expect(content.contains("Crashed"))
        #expect(content.contains("AXION_AUTH_KEY"))

        let calls = collector.calls
        #expect(calls.count == 2)
        #expect(calls[0][0] == "bootstrap")
        #expect(calls[1][0] == "kickstart")
    }

    @Test("Gateway status returns notInstalled when plist missing")
    func gatewayStatusNotInstalled() {
        let service = makeGatewayService(plistPath: "/tmp/nonexistent-\(UUID().uuidString)/test.plist")
        let result = service.status()
        #expect(result.status == .notInstalled)
        #expect(result.label == "dev.axion.gateway")
    }

    @Test("Gateway status returns stopped when launchctl fails")
    func gatewayStatusStopped() throws {
        let tempDir = NSTemporaryDirectory() + "axion-test-gw-stopped-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let plistPath = (tempDir as NSString).appendingPathComponent("dev.axion.gateway.plist")
        try "dummy".write(toFile: plistPath, atomically: true, encoding: .utf8)

        let service = makeGatewayService(plistPath: plistPath) { _ in
            throw DaemonError.launchctlFailed("print", 1)
        }
        let result = service.status()
        #expect(result.status == .stopped)
        #expect(result.label == "dev.axion.gateway")
    }

    @Test("Gateway uninstall removes plist")
    func gatewayUninstallRemovesPlist() throws {
        let tempDir = NSTemporaryDirectory() + "axion-test-gw-uninstall-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let plistPath = (tempDir as NSString).appendingPathComponent("dev.axion.gateway.plist")
        try "test".write(toFile: plistPath, atomically: true, encoding: .utf8)

        let service = DaemonService(
            label: "dev.axion.gateway",
            subcommand: "gateway start",
            logFileName: "gateway.log",
            errLogFileName: "gateway.err.log",
            plistPath: plistPath,
            runLaunchctl: { _ in "" },
            resolveBin: { "/usr/local/bin/axion" }
        )

        try service.uninstall()
        #expect(!FileManager.default.fileExists(atPath: plistPath))
    }

    @Test("Gateway uninstall with keepLogs=true still removes plist")
    func gatewayUninstallKeepLogsRemovesPlist() throws {
        let tempDir = NSTemporaryDirectory() + "axion-test-gw-keeplogs-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let plistPath = (tempDir as NSString).appendingPathComponent("dev.axion.gateway.plist")
        try "test".write(toFile: plistPath, atomically: true, encoding: .utf8)

        let service = DaemonService(
            label: "dev.axion.gateway",
            subcommand: "gateway start",
            logFileName: "gateway.log",
            errLogFileName: "gateway.err.log",
            plistPath: plistPath,
            runLaunchctl: { _ in "" },
            resolveBin: { "/usr/local/bin/axion" }
        )

        try service.uninstall(keepLogs: true)
        #expect(!FileManager.default.fileExists(atPath: plistPath))
    }
}
