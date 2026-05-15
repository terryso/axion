import Testing
import ArgumentParser
@testable import AxionCLI

@Suite("AxionCommand")
struct AxionCommandTests {

    // MARK: - AC1: `axion --help` 显示根命令帮助

    @Test("help output contains run subcommand")
    func axionHelpShowsRunSubcommand() {
        let helpText = AxionCLI.helpMessage(for: AxionCLI.self)
        #expect(
            helpText.contains("run"),
            "'--help' output should contain 'run' subcommand. Got:\n\(helpText)"
        )
    }

    @Test("help output contains setup subcommand")
    func axionHelpShowsSetupSubcommand() {
        let helpText = AxionCLI.helpMessage(for: AxionCLI.self)
        #expect(
            helpText.contains("setup"),
            "'--help' output should contain 'setup' subcommand. Got:\n\(helpText)"
        )
    }

    @Test("help output contains doctor subcommand")
    func axionHelpShowsDoctorSubcommand() {
        let helpText = AxionCLI.helpMessage(for: AxionCLI.self)
        #expect(
            helpText.contains("doctor"),
            "'--help' output should contain 'doctor' subcommand. Got:\n\(helpText)"
        )
    }

    // MARK: - AC2: `axion --version` 显示版本号

    @Test("configuration has version")
    func axionVersionConfigurationHasVersion() {
        let version = AxionCLI.configuration.version
        #expect(
            version.contains("0.1.0"),
            "Version should contain '0.1.0', got: \(version)"
        )
    }

    // MARK: - AC3: 未知子命令显示错误提示

    @Test("unknown subcommand throws parse error")
    func unknownSubcommandThrowsParseError() {
        do {
            _ = try AxionCLI.parse(["unknown"])
            Issue.record("Should have thrown an error")
        } catch is CleanExit {
            Issue.record("Unknown subcommand should produce a parse error, not CleanExit")
        } catch {
            // Expected: parse error
        }
    }

    // MARK: - RunCommand 参数解析

    @Test("run command parses task argument")
    func runCommandParsesTaskArgument() throws {
        let cmd = try RunCommand.parse(["打开计算器"])
        #expect(cmd.task == "打开计算器")
    }

    @Test("run command parses dryrun flag")
    func runCommandParsesDryrunFlag() throws {
        let cmd = try RunCommand.parse(["打开计算器", "--dryrun"])
        #expect(cmd.dryrun)
    }

    @Test("run command dryrun default is false")
    func runCommandDryrunDefaultIsFalse() throws {
        let cmd = try RunCommand.parse(["打开计算器"])
        #expect(!cmd.dryrun)
    }

    @Test("run command parses max-steps")
    func runCommandParsesMaxSteps() throws {
        let cmd = try RunCommand.parse(["打开计算器", "--max-steps", "5"])
        #expect(cmd.maxSteps == 5)
    }

    @Test("run command maxSteps default is nil")
    func runCommandMaxStepsDefaultIsNil() throws {
        let cmd = try RunCommand.parse(["打开计算器"])
        #expect(cmd.maxSteps == nil)
    }

    @Test("run command parses max-batches")
    func runCommandParsesMaxBatches() throws {
        let cmd = try RunCommand.parse(["打开计算器", "--max-batches", "3"])
        #expect(cmd.maxBatches == 3)
    }

    @Test("run command maxBatches default is nil")
    func runCommandMaxBatchesDefaultIsNil() throws {
        let cmd = try RunCommand.parse(["打开计算器"])
        #expect(cmd.maxBatches == nil)
    }

    @Test("run command parses allow-foreground flag")
    func runCommandParsesAllowForeground() throws {
        let cmd = try RunCommand.parse(["打开计算器", "--allow-foreground"])
        #expect(cmd.allowForeground)
    }

    @Test("run command parses verbose flag")
    func runCommandParsesVerbose() throws {
        let cmd = try RunCommand.parse(["打开计算器", "--verbose"])
        #expect(cmd.verbose)
    }

    @Test("run command parses json flag")
    func runCommandParsesJson() throws {
        let cmd = try RunCommand.parse(["打开计算器", "--json"])
        #expect(cmd.json)
    }

    @Test("run command requires task argument")
    func runCommandRequiresTaskArgument() {
        #expect(throws: Error.self) {
            _ = try RunCommand.parse([])
        }
    }

    @Test("run command parses all arguments combined")
    func runCommandParsesAllArgumentsCombined() throws {
        let cmd = try RunCommand.parse([
            "打开计算器并输入1+1",
            "--dryrun",
            "--max-steps", "10",
            "--max-batches", "4",
            "--allow-foreground",
            "--verbose",
            "--json"
        ])
        #expect(cmd.task == "打开计算器并输入1+1")
        #expect(cmd.dryrun)
        #expect(cmd.maxSteps == 10)
        #expect(cmd.maxBatches == 4)
        #expect(cmd.allowForeground)
        #expect(cmd.verbose)
        #expect(cmd.json)
    }

    // MARK: - SetupCommand 骨架验证

    @Test("setup command exists")
    func setupCommandExists() throws {
        _ = try SetupCommand.parse([])
    }

    // MARK: - DoctorCommand 骨架验证

    @Test("doctor command exists")
    func doctorCommandExists() throws {
        _ = try DoctorCommand.parse([])
    }

    // MARK: - AxionVersion 验证

    @Test("AxionVersion.current is not empty")
    func axionVersionCurrentIsNotEmpty() {
        #expect(!AxionVersion.current.isEmpty, "AxionVersion.current should not be empty")
    }

    @Test("AxionVersion.current matches VERSION file")
    func axionVersionMatchesVersionFile() {
        #expect(
            AxionVersion.current == "0.1.0",
            "AxionVersion.current should match VERSION file content"
        )
    }
}
