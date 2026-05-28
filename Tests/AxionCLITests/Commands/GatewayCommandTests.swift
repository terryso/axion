import Testing
import ArgumentParser
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
}
